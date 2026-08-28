@file:Suppress("OVERRIDE_DEPRECATION")

package com.aliumutaltas.booxsend

import android.companion.CompanionDeviceService
import android.content.Intent

class CompanionPresenceService : CompanionDeviceService() {
    @Suppress("DEPRECATION")
    override fun onDeviceAppeared(address: String) {
        // Companion apps are allowed to run while their associated device is
        // nearby. Starting as a regular service avoids BOOX firmware rejecting
        // a background foreground-service promotion immediately after boot.
        startService(Intent(this, TransferForegroundService::class.java))
    }

    @Suppress("DEPRECATION")
    override fun onDeviceDisappeared(address: String) {
        // Keep the RFCOMM record available for the Mac's next connection.
        // The listener blocks in accept() and performs no active scan or poll.
    }
}
