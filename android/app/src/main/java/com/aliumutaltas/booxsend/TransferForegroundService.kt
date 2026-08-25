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
    @Volatile private var serverSocket: BluetoothServerSocket? = null

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(Constants.CHANNEL_ID, "BOOX dosya aktarımı", NotificationManager.IMPORTANCE_LOW))
        startForeground(Constants.NOTIFICATION_ID, waitingNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Android expects every startForegroundService request to be acknowledged,
        // including a second presence event while this service is already running.
        startForeground(Constants.NOTIFICATION_ID, waitingNotification())
        if (!running.compareAndSet(false, true)) return START_NOT_STICKY
        executor.execute {
            try {
                val adapter = getSystemService(BluetoothManager::class.java).adapter
                adapter.listenUsingRfcommWithServiceRecord("BOOX Send", Constants.RFCOMM_SERVICE_UUID).use { server ->
                    serverSocket = server
                    while (running.get()) {
                        val socket = try {
                            // The service is event-driven and shuts itself down
                            // after a short idle period; there is no polling loop.
                            server.accept(15_000)
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
                        }
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
        return START_NOT_STICKY
    }

    private fun waitingNotification() = NotificationCompat.Builder(this, Constants.CHANNEL_ID)
        .setSmallIcon(android.R.drawable.stat_sys_upload)
        .setContentTitle("BOOX Send")
        .setContentText("Mac bağlantısı bekleniyor…")
        .setOngoing(true)
        .build()

    private fun updateNotification(text: String) {
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
