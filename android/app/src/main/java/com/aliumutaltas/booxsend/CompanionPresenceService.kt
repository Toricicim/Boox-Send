@file:Suppress("OVERRIDE_DEPRECATION")

package com.aliumutaltas.booxsend

import android.companion.CompanionDeviceService
import android.content.Intent
import android.util.Log

class CompanionPresenceService : CompanionDeviceService() {
    override fun onCreate() {
        super.onCreate()
        Log.i("BooxSend", "Companion presence service created")
    }

    @Suppress("DEPRECATION")
    override fun onDeviceAppeared(address: String) {
        Log.i("BooxSend", "Companion device appeared: $address")
        try {
            startService(Intent(this, TransferReceiverService::class.java))
        } catch (error: Exception) {
            Log.e("BooxSend", "Could not start temporary transfer receiver", error)
        }
    }

    @Suppress("DEPRECATION")
    override fun onDeviceDisappeared(address: String) {
        Log.i("BooxSend", "Companion device disappeared: $address")
    }

    override fun onDestroy() {
        Log.i("BooxSend", "Companion presence service destroyed")
        super.onDestroy()
    }
}
