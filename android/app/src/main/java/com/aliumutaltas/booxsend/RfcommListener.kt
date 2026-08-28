package com.aliumutaltas.booxsend

import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothManager
import android.content.Context
import android.util.Log
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class RfcommListener(
    private val context: Context,
    private val onTransferStarted: () -> Unit = {},
    private val onTransferFinished: (Boolean) -> Unit = {},
) {
    private val executor = Executors.newSingleThreadExecutor()
    private val running = AtomicBoolean(false)
    @Volatile private var serverSocket: BluetoothServerSocket? = null

    fun start() {
        if (!running.compareAndSet(false, true)) return
        Log.i("BooxSend", "Starting RFCOMM listener")
        executor.execute {
            try {
                val adapter = context.getSystemService(BluetoothManager::class.java).adapter
                while (running.get() && adapter.isEnabled) {
                    try {
                        adapter.listenUsingRfcommWithServiceRecord("BOOX Send", Constants.RFCOMM_SERVICE_UUID).use { server ->
                            serverSocket = server
                            Log.i("BooxSend", "RFCOMM service advertised; waiting for Mac")
                            while (running.get()) {
                                val socket = try {
                                    server.accept()
                                } catch (error: Exception) {
                                    if (running.get()) throw error
                                    break
                                }
                                var completed = false
                                try {
                                    socket.use {
                                        Log.i("BooxSend", "Mac connected to RFCOMM service")
                                        onTransferStarted()
                                        TransferSession(context, it.inputStream, it.outputStream).run()
                                        completed = true
                                    }
                                } catch (error: Exception) {
                                    if (running.get()) Log.e("BooxSend", "Transfer session failed", error)
                                } finally {
                                    onTransferFinished(completed)
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
            } finally {
                running.set(false)
            }
        }
    }

    fun stop() {
        if (running.get()) Log.i("BooxSend", "Stopping RFCOMM listener")
        running.set(false)
        runCatching { serverSocket?.close() }
        serverSocket = null
    }

    fun destroy() {
        stop()
        executor.shutdownNow()
    }
}
