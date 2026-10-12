package com.aliumutaltas.booxsend

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider

/** UI only. The application-scoped download owns no Activity or permanent service. */
class AppUpdater(private val activity: Activity, private val render: (String, Boolean, Boolean) -> Unit) {
    private val downloads = UpdateDownloads.get(activity)
    private var visible = false
    private val listener: (UpdateDownloads.State) -> Unit = { state ->
        if (visible) {
            render(state.message, state.busy, state.ready)
            when (val action = downloads.takeAction()) {
                is UpdateDownloads.Action.Offer -> offer(action.release)
                is UpdateDownloads.Action.Install -> installDownloaded()
                null -> Unit
            }
        }
    }

    fun resume() {
        visible = true
        downloads.observe(listener)
        if (downloads.waitingForPermission && activity.packageManager.canRequestPackageInstalls()) {
            downloads.waitingForPermission = false
            downloads.prepareInstall()
        } else {
            downloads.check(manual = false)
        }
    }

    fun pause() {
        visible = false
        downloads.removeObserver(listener)
    }

    fun check(manual: Boolean) { if (visible) downloads.check(manual) }
    fun installCached() { if (visible) downloads.prepareInstall() }

    private fun offer(release: UpdateDownloads.Release) {
        if (!visible) return
        val cached = downloads.matchesCached(release)
        AlertDialog.Builder(activity).setTitle("Update to ${release.tag}?")
            .setMessage("Your setup code, paired Mac and destination folder will be kept. Android will ask you to approve installation.")
            .setNegativeButton("Later", null)
            .setPositiveButton(if (cached) "Install Downloaded Update" else "Download Update") { _, _ ->
                if (visible) downloads.download(release)
            }.show()
    }

    private fun installDownloaded() {
        if (!visible) return
        try {
            check(!TransferReceiverService.transferActive) { "Finish the Bluetooth transfer, then tap Install Downloaded Update." }
            if (!activity.packageManager.canRequestPackageInstalls()) {
                AlertDialog.Builder(activity).setTitle("Allow update installation")
                    .setMessage("Enable Allow from this source for BOOX Send, then return here. Android will still ask you to approve the update.")
                    .setNegativeButton("Later", null)
                    .setPositiveButton("Open Settings") { _, _ ->
                        downloads.waitingForPermission = true
                        activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
                    }.show()
                return
            }
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", downloads.apk)
            activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            })
            downloads.setMessage("Approve the update in Android's installer. Your settings will be kept.")
        } catch (error: Exception) { downloads.setMessage(error.message ?: "Could not install update.") }
    }
}
