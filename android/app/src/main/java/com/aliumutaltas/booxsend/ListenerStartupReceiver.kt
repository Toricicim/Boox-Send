package com.aliumutaltas.booxsend

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class ListenerStartupReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val shouldStart = when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> bluetoothIsEnabled(context)
            BluetoothAdapter.ACTION_STATE_CHANGED ->
                intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR) == BluetoothAdapter.STATE_ON
            else -> false
        }

        if (shouldStart) {
            try {
                context.startService(Intent(context, TransferForegroundService::class.java))
            } catch (error: IllegalStateException) {
                // Companion presence remains the primary background-start path.
                Log.w("BooxSend", "Boot listener start deferred to companion presence", error)
            }
        }
    }

    private fun bluetoothIsEnabled(context: Context): Boolean =
        context.getSystemService(BluetoothManager::class.java).adapter?.isEnabled == true
}
