package com.aliumutaltas.booxsend

import android.app.Service
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log

class TransferReceiverService : Service() {
    private lateinit var listener: RfcommListener
    private val handler = Handler(Looper.getMainLooper())
    private val stopAfterIdle = Runnable {
        Log.i("BooxSend", "Temporary receiver window expired")
        stopSelf()
    }

    override fun onCreate() {
        super.onCreate()
        listener = RfcommListener(
            this,
            onTransferStarted = { handler.removeCallbacks(stopAfterIdle) },
            onTransferFinished = { completed ->
                if (completed) {
                    Log.i("BooxSend", "Transfer completed; stopping temporary receiver")
                    stopSelf()
                } else {
                    scheduleIdleTimeout()
                }
            },
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i("BooxSend", "Temporary transfer receiver started")
        listener.start()
        scheduleIdleTimeout()
        return START_NOT_STICKY
    }

    private fun scheduleIdleTimeout() {
        handler.removeCallbacks(stopAfterIdle)
        handler.postDelayed(stopAfterIdle, RECEIVER_WINDOW_MS)
    }

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() {
        handler.removeCallbacks(stopAfterIdle)
        listener.destroy()
        Log.i("BooxSend", "Temporary transfer receiver stopped")
        super.onDestroy()
    }

    private companion object {
        const val RECEIVER_WINDOW_MS = 120_000L
    }
}
