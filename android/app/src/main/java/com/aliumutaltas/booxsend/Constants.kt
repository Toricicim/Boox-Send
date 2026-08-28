package com.aliumutaltas.booxsend

import java.util.UUID

object Constants {
    val RFCOMM_SERVICE_UUID: UUID = UUID.fromString("C2D4A9F8-4E53-4A2C-91CE-77421C8F78B2")
    const val PROTOCOL_VERSION = 1
    const val PREFS = "boox_send"
    const val KEY_TREE_URI = "tree_uri"
    const val KEY_SETUP_CODE = "setup_code"
    const val KEY_COMPANION_ADDRESS = "companion_address"
    const val CHANNEL_ID = "boox_send_transfer"
    const val NOTIFICATION_ID = 1001
    const val EXTRA_FOREGROUND = "foreground"
}
