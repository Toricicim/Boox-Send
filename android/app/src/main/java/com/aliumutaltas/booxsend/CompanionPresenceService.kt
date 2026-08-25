@file:Suppress("OVERRIDE_DEPRECATION")

package com.aliumutaltas.booxsend

import android.companion.CompanionDeviceService
import android.content.Intent
import android.os.Build

class CompanionPresenceService : CompanionDeviceService() {
    @Suppress("DEPRECATION")
    override fun onDeviceAppeared(address: String) {
        val intent = Intent(this, TransferForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
    }

    @Suppress("DEPRECATION")
    override fun onDeviceDisappeared(address: String) {
        stopService(Intent(this, TransferForegroundService::class.java))
    }
}
