package com.aliumutaltas.booxsend

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothManager
import android.content.Intent
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class TransferForegroundService : Service() {
    private val executor = Executors.newSingleThreadExecutor()
    private val running = AtomicBoolean(false)
    @Volatile private var foregroundMode = false
    @Volatile private var serverSocket: BluetoothServerSocket? = null

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(Constants.CHANNEL_ID, "BOOX dosya aktarımı", NotificationManager.IMPORTANCE_LOW))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.getBooleanExtra(Constants.EXTRA_FOREGROUND, false) == true) {
            // A manual app launch uses a foreground start as a fallback. Companion
            // presence and boot starts remain regular background service starts.
            foregroundMode = true
            startForeground(Constants.NOTIFICATION_ID, waitingNotification())
        }
        if (!running.compareAndSet(false, true)) return START_STICKY
        executor.execute {
            try {
                val adapter = getSystemService(BluetoothManager::class.java).adapter
                while (running.get() && adapter.isEnabled) {
                    try {
                        adapter.listenUsingRfcommWithServiceRecord("BOOX Send", Constants.RFCOMM_SERVICE_UUID).use { server ->
                            serverSocket = server
                            while (running.get()) {
                                val socket = try {
                                    // A blocking accept keeps the RFCOMM service advertised
                                    // without scanning, polling, timers, or CPU wake-ups.
                                    server.accept()
                                } catch (error: Exception) {
                                    if (running.get()) throw error
                                    break
                                }
                                try {
                                    socket.use {
                                        updateNotification("Dosyalar alınıyor…")
                                        TransferSession(this, it.inputStream, it.outputStream).run()
                                        updateNotification("Mac bağlantısı bekleniyor…")
                                    }
                                } catch (error: Exception) {
                                    if (running.get()) Log.e("BooxSend", "Transfer session failed", error)
                                    updateNotification("Mac bağlantısı bekleniyor…")
                                }
                            }
                        }
                    } catch (error: Exception) {
                        if (!running.get() || !adapter.isEnabled) break
                        Log.e("BooxSend", "RFCOMM listener failed; retrying", error)
                        Thread.sleep(1_000)
                    } finally {
                        serverSocket = null
                    }
                }
            } catch (error: Exception) {
                if (running.get()) Log.e("BooxSend", "RFCOMM listener failed", error)
            } finally {
                serverSocket = null
                running.set(false)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_STICKY
    }

    private fun waitingNotification() = NotificationCompat.Builder(this, Constants.CHANNEL_ID)
        .setSmallIcon(android.R.drawable.stat_sys_upload)
        .setContentTitle("BOOX Send")
        .setContentText("Mac bağlantısı bekleniyor…")
        .setOngoing(true)
        .build()

    private fun updateNotification(text: String) {
        if (!foregroundMode) return
        val notification = NotificationCompat.Builder(this, Constants.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("BOOX Send")
            .setContentText(text)
            .setOngoing(true)
            .build()
        getSystemService(NotificationManager::class.java).notify(Constants.NOTIFICATION_ID, notification)
    }

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() {
        running.set(false)
        runCatching { serverSocket?.close() }
        executor.shutdownNow()
        super.onDestroy()
    }
}
