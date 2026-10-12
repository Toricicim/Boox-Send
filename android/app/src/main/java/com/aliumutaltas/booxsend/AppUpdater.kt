package com.aliumutaltas.booxsend

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import kotlin.concurrent.thread

/** Only invoked by the visible setup Activity; never by Bluetooth or boot events. */
class AppUpdater(private val activity: Activity, private val showStatus: (String) -> Unit) {
    private data class Release(val tag: String, val url: String, val digest: String)
    private val prefs = activity.getSharedPreferences("updates", Activity.MODE_PRIVATE)
    private var busy = false
    private var available: Release? = null
    private val apk get() = File(activity.cacheDir, "updates/BOOX-Send-android.apk")

    fun check(manual: Boolean) {
        if (busy) return
        if (manual && available != null) { offer(available!!); return }
        if (!manual && System.currentTimeMillis() - prefs.getLong("lastCheck", 0) < 24 * 60 * 60 * 1000L) return
        prefs.edit().putLong("lastCheck", System.currentTimeMillis()).apply()
        work("Checking for updates…", manual) {
            val json = connection("https://api.github.com/repos/Toricicim/Boox-Send/releases/latest") { conn ->
                conn.inputStream.bufferedReader().use { JSONObject(it.readText()) }
            }
            check(!json.optBoolean("draft") && !json.optBoolean("prerelease")) { "No stable release available." }
            val tag = json.getString("tag_name")
            val installed = activity.packageManager.getPackageInfo(activity.packageName, 0).versionName.orEmpty()
            if (!UpdatePolicy.isNewer(tag, installed)) {
                ui { showStatus("Up to date ($installed).") }
                return@work
            }
            val assets = json.getJSONArray("assets")
            val asset = (0 until assets.length()).map { assets.getJSONObject(it) }
                .firstOrNull { it.getString("name") == "BOOX-Send-android.apk" }
                ?: error("The Android update is not available yet.")
            val release = Release(tag, asset.getString("browser_download_url"), asset.getString("digest"))
            check(UpdatePolicy.validAsset(release.url, release.digest)) { "Invalid update metadata." }
            ui {
                available = release
                showStatus("Update ${release.tag} available. Tap Check for Updates to install.")
                if (manual) offer(release)
            }
        }
    }

    private fun offer(release: Release) {
        AlertDialog.Builder(activity).setTitle("Update to ${release.tag}?")
            .setMessage("Your setup code, paired Mac and destination folder will be kept. Internet is required to download the update. Android will ask you to approve installation.")
            .setNegativeButton("Later", null)
            .setPositiveButton("Download Update") { _, _ -> download(release) }.show()
    }

    private fun download(release: Release) {
        work("Downloading ${release.tag}…", true) {
            apk.parentFile!!.mkdirs()
            val partial = File(apk.parentFile, "download.part")
            try {
                val digest = MessageDigest.getInstance("SHA-256")
                connection(release.url) { conn ->
                    conn.inputStream.use { input -> partial.outputStream().use { output ->
                        val buffer = ByteArray(32768)
                        var total = 0L
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            total += count
                            check(total <= 100 * 1024 * 1024) { "Update exceeds the download limit." }
                            digest.update(buffer, 0, count)
                            output.write(buffer, 0, count)
                        }
                    } }
                }
                val hash = digest.digest().joinToString("") { "%02x".format(it) }
                check("sha256:$hash" == release.digest) { "Update checksum failed. Please retry." }
                validateApk(partial, release.tag)
                if (apk.exists()) check(apk.delete()) { "Could not replace cached update." }
                check(partial.renameTo(apk)) { "Could not save update." }
                prefs.edit().putString("downloadedTag", release.tag).apply()
                ui { installDownloaded() }
            } finally { partial.delete() }
        }
    }

    private fun validateApk(file: File, tag: String) {
        val pm = activity.packageManager
        val candidate = pm.getPackageArchiveInfo(file.path, PackageManager.GET_SIGNING_CERTIFICATES)
            ?: error("Invalid update APK.")
        val current = pm.getPackageInfo(activity.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        check(candidate.packageName == current.packageName && candidate.versionName == tag.removePrefix("v") &&
            candidate.longVersionCode > current.longVersionCode) { "APK version or application identity does not match." }
        val nextSigners = candidate.signingInfo?.apkContentsSigners?.toSet()
        val currentSigners = current.signingInfo?.apkContentsSigners?.toSet()
        check(!nextSigners.isNullOrEmpty() && nextSigners == currentSigners) {
            "This app uses a different signing key (for example a source/debug build). Automatic release updates cannot replace it safely. Keep this installation and update using the same signing key; do not uninstall to fix this."
        }
    }

    fun resumePendingInstall() {
        if (prefs.getBoolean("waitingForInstallPermission", false) && activity.packageManager.canRequestPackageInstalls()) {
            prefs.edit().putBoolean("waitingForInstallPermission", false).apply()
            installDownloaded()
        }
    }

    private fun installDownloaded() {
        try {
            check(!TransferReceiverService.transferActive) { "Finish the Bluetooth transfer before installing an update." }
            validateApk(apk, prefs.getString("downloadedTag", "").orEmpty())
            if (!activity.packageManager.canRequestPackageInstalls()) {
                AlertDialog.Builder(activity).setTitle("Allow update installation")
                    .setMessage("Enable Allow from this source for BOOX Send, then return here. Android will still ask you to approve the update.")
                    .setNegativeButton("Later", null)
                    .setPositiveButton("Open Settings") { _, _ ->
                        prefs.edit().putBoolean("waitingForInstallPermission", true).apply()
                        activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
                    }.show()
                return
            }
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", apk)
            activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            })
            showStatus("Approve the update in Android's installer. Your settings will be kept.")
        } catch (error: Exception) { showStatus(error.message ?: "Could not install update.") }
    }

    private fun work(message: String, manual: Boolean, action: () -> Unit) {
        busy = true
        showStatus(message)
        thread(name = "booxsend-update") {
            try { action() } catch (error: Exception) {
                ui { showStatus(if (manual) "Update failed: ${error.message}" else "Could not check for updates. Bluetooth transfers still work offline.") }
            } finally { activity.runOnUiThread { busy = false } }
        }
    }

    private fun ui(action: () -> Unit) {
        activity.runOnUiThread { if (!activity.isFinishing && !activity.isDestroyed) action() }
    }

    private fun <T> connection(url: String, action: (HttpURLConnection) -> T): T {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 15000
        conn.readTimeout = 30000
        conn.setRequestProperty("User-Agent", "BOOX-Send-Updater")
        conn.setRequestProperty("Accept", "application/vnd.github+json")
        try {
            check(conn.responseCode in 200..299) { "Server returned ${conn.responseCode}." }
            check(conn.url.protocol == "https") { "Update requires HTTPS." }
            return action(conn)
        } finally { conn.disconnect() }
    }
}
