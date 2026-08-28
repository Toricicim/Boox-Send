package com.aliumutaltas.booxsend

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.companion.CompanionDeviceManager
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
            restorePresenceObservation(context)
        }
    }

    private fun bluetoothIsEnabled(context: Context): Boolean =
        context.getSystemService(BluetoothManager::class.java).adapter?.isEnabled == true

    @Suppress("DEPRECATION")
    private fun restorePresenceObservation(context: Context) {
        val prefs = context.getSharedPreferences(Constants.PREFS, Context.MODE_PRIVATE)
        val manager = context.getSystemService(CompanionDeviceManager::class.java)
        val address = prefs.getString(Constants.KEY_COMPANION_ADDRESS, null)
            ?: manager.associations.firstOrNull()
            ?: return
        try {
            manager.startObservingDevicePresence(address)
        } catch (error: Exception) {
            Log.w("BooxSend", "Could not restore companion presence observation", error)
        }
    }
}
