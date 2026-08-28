package com.aliumutaltas.booxsend

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.bluetooth.BluetoothDevice
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
import androidx.core.content.ContextCompat
import java.util.regex.Pattern

class MainActivity : Activity() {
    private val prefs by lazy { getSharedPreferences(Constants.PREFS, MODE_PRIVATE) }
    private lateinit var status: TextView
    private lateinit var code: EditText

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestBluetoothPermissions()

        val padding = (24 * resources.displayMetrics.density).toInt()
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding, padding, padding)
            addView(TextView(context).apply { text = "BOOX Send İlk Kurulum"; textSize = 24f })
        }
        code = EditText(this).apply {
            hint = "Mac'teki 8 karakterli kurulum kodu"
            setText(prefs.getString(Constants.KEY_SETUP_CODE, ""))
            isSingleLine = true
        }
        layout.addView(code, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        layout.addView(Button(this).apply {
            text = "Kodu Kaydet"
            setOnClickListener {
                prefs.edit().putString(Constants.KEY_SETUP_CODE, code.text.toString().trim().uppercase()).apply()
                updateStatus("Kurulum kodu kaydedildi.")
            }
        })
        layout.addView(Button(this).apply {
            text = "Hedef Klasörü Seç"
            setOnClickListener {
                startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                }, REQUEST_TREE)
            }
        })
        layout.addView(Button(this).apply {
            text = "Mac'i Companion Cihaz Olarak Eşleştir"
            setOnClickListener { associateMac() }
        })
        layout.addView(Button(this).apply {
            text = "Uygulama Ayarlarını Aç"
            setOnClickListener {
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
            }
        })
        status = TextView(this).apply { setPadding(0, padding, 0, 0) }
        layout.addView(status)
        setContentView(layout)
        refreshStatus()
    }

    override fun onResume() {
        super.onResume()
        restoreSystemCompanionAssociation()
        startTransferListener()
        if (::status.isInitialized) refreshStatus()
    }

    private fun startTransferListener() {
        ContextCompat.startForegroundService(
            this,
            Intent(this, TransferForegroundService::class.java)
                .putExtra(Constants.EXTRA_FOREGROUND, true),
        )
    }

    private fun requestBluetoothPermissions() {
        val permissions = mutableListOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        if (android.os.Build.VERSION.SDK_INT >= 33) permissions += Manifest.permission.POST_NOTIFICATIONS
        val missing = permissions.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isNotEmpty()) requestPermissions(missing.toTypedArray(), REQUEST_PERMISSIONS)
    }

    private fun associateMac() {
        if (code.text.toString().trim().length != 8) {
            updateStatus("Önce 8 karakterli kurulum kodunu kaydedin.")
            return
        }
        val deviceFilter = BluetoothDeviceFilter.Builder().setNamePattern(Pattern.compile(".*")).build()
        val request = AssociationRequest.Builder().addDeviceFilter(deviceFilter).setSingleDevice(true).build()
        val manager = getSystemService(CompanionDeviceManager::class.java)
        manager.associate(request, object : CompanionDeviceManager.Callback() {
            @Deprecated("Android 12 callback")
            override fun onDeviceFound(chooserLauncher: IntentSender) {
                startIntentSenderForResult(chooserLauncher, REQUEST_ASSOCIATION, null, 0, 0, 0)
            }

            override fun onFailure(error: CharSequence?) {
                runOnUiThread { updateStatus("Mac bulunamadı: ${error ?: "bilinmeyen hata"}") }
            }
        }, null)
        updateStatus("Yakındaki Classic Bluetooth cihazları aranıyor; eşleştirilmiş Mac'inizi seçin…")
    }

    /**
     * Some BOOX firmware opens the generic Bluetooth settings screen instead of
     * returning the companion chooser result. Recover an association already
     * recorded by Android so presence observation still works on those devices.
     */
    @Suppress("DEPRECATION")
    private fun restoreSystemCompanionAssociation() {
        val manager = getSystemService(CompanionDeviceManager::class.java)
        val address = prefs.getString(Constants.KEY_COMPANION_ADDRESS, null)
            ?: manager.associations.firstOrNull()?.also {
                prefs.edit().putString(Constants.KEY_COMPANION_ADDRESS, it).apply()
            }
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
        if (resultCode != RESULT_OK || data == null) return
        when (requestCode) {
            REQUEST_TREE -> data.data?.let { uri ->
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                prefs.edit().putString(Constants.KEY_TREE_URI, uri.toString()).apply()
                refreshStatus()
            }
            REQUEST_ASSOCIATION -> {
                @Suppress("DEPRECATION")
                val device = data.getParcelableExtra<BluetoothDevice>(CompanionDeviceManager.EXTRA_DEVICE)
                if (device != null) {
                    prefs.edit().putString(Constants.KEY_COMPANION_ADDRESS, device.address).apply()
                    try {
                        getSystemService(CompanionDeviceManager::class.java).startObservingDevicePresence(device.address)
                        updateStatus("Mac companion cihaz olarak eşleştirildi.")
                    } catch (error: Exception) {
                        updateStatus("Varlık izleme başlatılamadı: ${error.message}")
                    }
                }
            }
        }
    }

    private fun refreshStatus() {
        val folder = prefs.getString(Constants.KEY_TREE_URI, null) != null
        val companion = prefs.getString(Constants.KEY_COMPANION_ADDRESS, null) != null
        val savedCode = !prefs.getString(Constants.KEY_SETUP_CODE, "").isNullOrBlank()
        updateStatus("Kod: ${if (savedCode) "hazır" else "eksik"}\nHedef klasör: ${if (folder) "hazır" else "eksik"}\nMac companion: ${if (companion) "hazır" else "eksik"}")
    }

    private fun updateStatus(message: String) { status.text = message }

    companion object {
        private const val REQUEST_TREE = 10
        private const val REQUEST_ASSOCIATION = 11
        private const val REQUEST_PERMISSIONS = 12
    }
}
