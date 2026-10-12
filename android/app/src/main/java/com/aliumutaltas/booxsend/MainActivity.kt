package com.aliumutaltas.booxsend

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.companion.AssociationRequest
import android.companion.BluetoothDeviceFilter
import android.companion.CompanionDeviceManager
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

class MainActivity : Activity() {
    private val prefs by lazy { getSharedPreferences(Constants.PREFS, MODE_PRIVATE) }
    private lateinit var status: TextView
    private lateinit var code: EditText
    private var pendingCompanionAddress: String? = null
    private lateinit var updater: AppUpdater

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingCompanionAddress = savedInstanceState?.getString("pendingCompanionAddress")
        requestBluetoothPermissions()

        val padding = (24 * resources.displayMetrics.density).toInt()
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding, padding, padding)
            addView(TextView(context).apply { text = "BOOX Send Setup"; textSize = 24f })
        }
        code = EditText(this).apply {
            hint = "8-character setup code from the Mac"
            setText(prefs.getString(Constants.KEY_SETUP_CODE, ""))
            isSingleLine = true
        }
        layout.addView(code, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        layout.addView(Button(this).apply {
            text = "Save Code"
            setOnClickListener {
                prefs.edit().putString(Constants.KEY_SETUP_CODE, code.text.toString().trim().uppercase()).apply()
                updateStatus("Setup code saved.")
            }
        })
        layout.addView(Button(this).apply {
            text = "Choose Destination Folder"
            setOnClickListener {
                startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                }, REQUEST_TREE)
            }
        })
        layout.addView(Button(this).apply {
            text = "Associate Mac as Companion Device"
            setOnClickListener { associateMac() }
        })
        layout.addView(Button(this).apply {
            text = "Open App Settings"
            setOnClickListener {
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
            }
        })
        status = TextView(this).apply { setPadding(0, padding, 0, 0) }
        layout.addView(status)
        val updateStatus = TextView(this)
        val checkUpdates = Button(this).apply {
            text = "Check for Updates"
        }
        val installUpdate = Button(this).apply {
            text = "Install Downloaded Update"
            visibility = android.view.View.GONE
        }
        updater = AppUpdater(this) { message, busy, ready ->
            updateStatus.text = message
            checkUpdates.isEnabled = !busy
            installUpdate.isEnabled = !busy
            installUpdate.visibility = if (ready) android.view.View.VISIBLE else android.view.View.GONE
        }
        checkUpdates.setOnClickListener { updater.check(manual = true) }
        installUpdate.setOnClickListener { updater.installCached() }
        layout.addView(checkUpdates)
        layout.addView(installUpdate)
        layout.addView(updateStatus)
        setContentView(layout)
        refreshStatus()
    }

    override fun onResume() {
        super.onResume()
        restoreSystemCompanionAssociation()
        startTemporaryReceiverIfConfigured()
        if (::status.isInitialized) refreshStatus()
        if (::updater.isInitialized) {
            updater.resume()
        }
    }

    override fun onPause() {
        if (::updater.isInitialized) updater.pause()
        super.onPause()
    }

    override fun onDestroy() {
        if (::updater.isInitialized) updater.pause()
        super.onDestroy()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("pendingCompanionAddress", pendingCompanionAddress)
        super.onSaveInstanceState(outState)
    }

    private fun startTemporaryReceiverIfConfigured() {
        val setupComplete = !prefs.getString(Constants.KEY_SETUP_CODE, "").isNullOrBlank() &&
            !prefs.getString(Constants.KEY_TREE_URI, "").isNullOrBlank()
        if (!setupComplete || checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) return
        try {
            startService(Intent(this, TransferReceiverService::class.java))
        } catch (_: Exception) {
            // The Bluetooth system event remains the normal wake-up path.
        }
    }

    private fun requestBluetoothPermissions() {
        val permissions = mutableListOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        val missing = permissions.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isNotEmpty()) requestPermissions(missing.toTypedArray(), REQUEST_PERMISSIONS)
    }

    private fun associateMac() {
        if (prefs.getString(Constants.KEY_SETUP_CODE, "").orEmpty().length != 8) {
            updateStatus("Save an 8-character setup code first.")
            return
        }
        if (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
            requestBluetoothPermissions()
            updateStatus("Allow Nearby devices access, then tap Associate Mac again.")
            return
        }
        val adapter = getSystemService(BluetoothManager::class.java).adapter
        if (adapter == null || !adapter.isEnabled) {
            updateStatus("Turn on Bluetooth on both devices, then tap Associate Mac again.")
            return
        }
        val devices = adapter.bondedDevices.sortedWith(compareBy({ it.name.orEmpty() }, { it.address }))
        if (devices.isEmpty()) {
            updateStatus("No paired devices found. Pair your Mac in the BOOX Bluetooth settings first.")
            startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
            return
        }
        AlertDialog.Builder(this)
            .setTitle("Select your paired Mac")
            .setItems(devices.map { "${it.name ?: "Unnamed device"}\n${it.address}" }.toTypedArray()) { _, index ->
                associatePairedMac(devices[index])
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun associatePairedMac(device: BluetoothDevice) {
        val manager = getSystemService(CompanionDeviceManager::class.java)
        @Suppress("DEPRECATION")
        if (manager.associations.any { it.equals(device.address, ignoreCase = true) }) {
            saveCompanion(device.address)
            return
        }
        pendingCompanionAddress = device.address
        // An exact address also lets Android match an already-bonded device
        // without requiring it to be discoverable. Never match nearby strangers.
        val deviceFilter = BluetoothDeviceFilter.Builder().setAddress(device.address).build()
        val request = AssociationRequest.Builder().addDeviceFilter(deviceFilter).setSingleDevice(true).build()
        updateStatus("Requesting companion access for ${device.name ?: device.address}…")
        try {
            manager.associate(request, object : CompanionDeviceManager.Callback() {
                @Deprecated("Android 12 callback")
                override fun onDeviceFound(chooserLauncher: IntentSender) {
                    startIntentSenderForResult(chooserLauncher, REQUEST_ASSOCIATION, null, 0, 0, 0)
                }

                override fun onFailure(error: CharSequence?) {
                    runOnUiThread {
                        pendingCompanionAddress = null
                        updateStatus("Could not associate your Mac: ${error ?: "unknown error"}. Check Bluetooth is on and try again.")
                    }
                }
            }, null)
        } catch (error: Exception) {
            pendingCompanionAddress = null
            updateStatus("Could not associate your Mac: ${error.message}")
        }
    }

    private fun saveCompanion(address: String) {
        prefs.edit().putString(Constants.KEY_COMPANION_ADDRESS, address).apply()
        pendingCompanionAddress = null
        try {
            getSystemService(CompanionDeviceManager::class.java).startObservingDevicePresence(address)
            updateStatus("Mac associated as a companion device.")
        } catch (error: Exception) {
            updateStatus("Mac associated, but could not start presence observation: ${error.message}")
        }
    }

    /**
     * Some BOOX firmware opens the generic Bluetooth settings screen instead of
     * returning the companion chooser result. Recover an association already
     * recorded by Android so presence observation still works on those devices.
     */
    @Suppress("DEPRECATION")
    private fun restoreSystemCompanionAssociation() {
        val manager = getSystemService(CompanionDeviceManager::class.java)
        val associations = manager.associations
        // Recover only the Mac explicitly selected in this association flow.
        // Older broad scans may have recorded a neighbour's device.
        val address = pendingCompanionAddress?.takeIf { selected ->
            associations.any { it.equals(selected, ignoreCase = true) }
        }?.also {
            prefs.edit().putString(Constants.KEY_COMPANION_ADDRESS, it).apply()
        }
            ?: prefs.getString(Constants.KEY_COMPANION_ADDRESS, null)
            ?: return

        try {
            manager.startObservingDevicePresence(address)
        } catch (_: Exception) {
            // Already observing, or Bluetooth is temporarily unavailable.
        }
    }

    @Deprecated("Android 12 result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_ASSOCIATION) {
            @Suppress("DEPRECATION")
            val device = data?.getParcelableExtra<BluetoothDevice>(CompanionDeviceManager.EXTRA_DEVICE)
            val selected = pendingCompanionAddress
            @Suppress("DEPRECATION")
            val associated = selected?.takeIf { address ->
                getSystemService(CompanionDeviceManager::class.java).associations.any {
                    it.equals(address, ignoreCase = true)
                }
            }
            if (associated != null) {
                saveCompanion(associated)
            } else if (resultCode == RESULT_OK && device != null && device.address.equals(selected, ignoreCase = true)) {
                saveCompanion(device.address)
            } else {
                pendingCompanionAddress = null
                updateStatus("Mac association was not completed. Tap Associate Mac to try again.")
            }
            return
        }
        if (resultCode != RESULT_OK || data == null) return
        when (requestCode) {
            REQUEST_TREE -> data.data?.let { uri ->
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                prefs.edit().putString(Constants.KEY_TREE_URI, uri.toString()).apply()
                refreshStatus()
            }
        }
    }

    private fun refreshStatus() {
        val folder = prefs.getString(Constants.KEY_TREE_URI, null) != null
        val companion = prefs.getString(Constants.KEY_COMPANION_ADDRESS, null) != null
        val savedCode = !prefs.getString(Constants.KEY_SETUP_CODE, "").isNullOrBlank()
        updateStatus("Code: ${if (savedCode) "ready" else "missing"}\nDestination folder: ${if (folder) "ready" else "missing"}\nMac companion: ${if (companion) "ready" else "missing"}")
    }

    private fun updateStatus(message: String) { status.text = message }

    companion object {
        private const val REQUEST_TREE = 10
        private const val REQUEST_ASSOCIATION = 11
        private const val REQUEST_PERMISSIONS = 12
    }
}
