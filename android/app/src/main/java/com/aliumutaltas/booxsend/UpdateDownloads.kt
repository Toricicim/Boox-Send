package com.aliumutaltas.booxsend

import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import kotlin.concurrent.thread

/** Created by setup UI only. One bounded thread per operation; no scheduler or wake-up. */
class UpdateDownloads internal constructor(private val context: Context, private val source: UpdateSource = GitHubUpdateSource) {
    data class Release(val tag: String, val url: String, val digest: String, val size: Long)
    data class State(val message: String, val busy: Boolean, val ready: Boolean)
    sealed class Action {
        data class Offer(val release: Release) : Action()
        object Install : Action()
    }
    private data class Result(val message: String, val action: Action? = null)
    private val prefs = context.getSharedPreferences("updates", Context.MODE_PRIVATE)
    private val handler = Handler(Looper.getMainLooper())
    private val gate = UpdateOperationGate()
    private val observers = mutableSetOf<(State) -> Unit>()
    private var message = ""
    private var action: Action? = null
    val apk get() = File(context.cacheDir, "updates/BOOX-Send-android.apk")
    private val installedVersion = context.packageManager.getPackageInfo(context.packageName, 0).versionName.orEmpty()

    var waitingForPermission: Boolean
        get() = prefs.getBoolean("waitingForInstallPermission", false)
        set(value) { prefs.edit().putBoolean("waitingForInstallPermission", value).apply() }

    private val cachedTag get() = prefs.getString("readyTag", "").orEmpty()
    private val cachedDigest get() = prefs.getString("readyDigest", "").orEmpty()
    private val ready get() = apk.isFile && UpdatePolicy.isNewer(cachedTag, installedVersion) &&
        Regex("^sha256:[0-9a-f]{64}$").matches(cachedDigest)

    fun observe(observer: (State) -> Unit) {
        observers.add(observer)
        if (message.isEmpty() && ready) message = "Update $cachedTag downloaded. Tap Install Downloaded Update."
        observer(state())
    }
    fun removeObserver(observer: (State) -> Unit) { observers.remove(observer) }
    fun takeAction(): Action? = action.also { action = null }
    fun setMessage(value: String) { message = value; notifyObservers() }
    private fun state() = State(message, gate.isBusy, ready)
    private fun notifyObservers() { val snapshot = state(); observers.toList().forEach { it(snapshot) } }

    fun matchesCached(release: Release): Boolean = ready && cachedTag == release.tag && cachedDigest == release.digest

    fun check(manual: Boolean) {
        val now = System.currentTimeMillis()
        if (!manual && !UpdatePolicy.shouldAutomaticallyCheck(now, prefs.getLong("lastSuccess", 0), prefs.getLong("lastAttempt", 0))) return
        runJob("Checking for updates…", manual) {
            prefs.edit().putLong("lastAttempt", now).apply()
            val release = source.latest()
            val tag = release.tag
            val installed = installedVersion
            if (!UpdatePolicy.isNewer(tag, installed)) {
                prefs.edit().putLong("lastSuccess", now).apply()
                return@runJob Result("Up to date ($installed).")
            }
            check(UpdatePolicy.validAsset(release.url, release.digest) && release.size in 1..MAX_DOWNLOAD_BYTES) { "Invalid update metadata." }
            prefs.edit().putLong("lastSuccess", now).apply()
            Result("Update ${release.tag} available. Tap Check for Updates to install.", if (manual) Action.Offer(release) else null)
        }
    }

    fun download(release: Release) {
        runJob("Preparing ${release.tag}…", true) {
            if (matchesCached(release)) {
                validateCached()
                return@runJob Result("Downloaded update verified.", Action.Install)
            }
            check(UpdatePolicy.validAsset(release.url, release.digest) && release.size in 1..MAX_DOWNLOAD_BYTES) { "Invalid update metadata." }
            apk.parentFile!!.mkdirs()
            val partial = File.createTempFile("download-", ".partial.apk", apk.parentFile)
            try {
                val digest = MessageDigest.getInstance("SHA-256")
                source.openDownload(release.url).use { input -> partial.outputStream().use { output ->
                        val buffer = ByteArray(32768)
                        var total = 0L
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            total += count
                            check(total <= release.size && total <= MAX_DOWNLOAD_BYTES) { "Update exceeds the download limit." }
                            digest.update(buffer, 0, count)
                            output.write(buffer, 0, count)
                        }
                        check(total == release.size) { "The update download is incomplete." }
                } }
                check("sha256:${hex(digest.digest())}" == release.digest) { "Update checksum failed. Please retry." }
                validateApk(partial, release.tag)
                Files.move(partial.toPath(), apk.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
                check(prefs.edit().putString("readyTag", release.tag).putString("readyDigest", release.digest).commit()) { "Could not save update metadata." }
                Result("Update ${release.tag} downloaded and verified.", Action.Install)
            } finally { partial.delete() }
        }
    }

    fun prepareInstall() {
        runJob("Verifying downloaded update…", true) {
            check(!TransferReceiverService.transferActive) { "Finish the Bluetooth transfer, then tap Install Downloaded Update." }
            validateCached()
            Result("Downloaded update verified.", Action.Install)
        }
    }

    private fun validateCached() {
        try { validateCachedContents() } catch (error: Exception) {
            prefs.edit().remove("readyTag").remove("readyDigest").commit()
            throw error
        }
    }

    private fun validateCachedContents() {
        check(ready) { "No newer downloaded update is ready. Tap Check for Updates." }
        val digest = MessageDigest.getInstance("SHA-256")
        apk.inputStream().use { input ->
            val buffer = ByteArray(32768)
            var total = 0L
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                total += count
                check(total <= MAX_DOWNLOAD_BYTES) { "Cached update exceeds the size limit." }
                digest.update(buffer, 0, count)
            }
        }
        check("sha256:${hex(digest.digest())}" == cachedDigest) { "Cached update checksum failed. Tap Check for Updates to download again." }
        validateApk(apk, cachedTag)
    }

    private fun validateApk(file: File, tag: String) {
        val pm = context.packageManager
        val candidate = pm.getPackageArchiveInfo(file.path, PackageManager.GET_SIGNING_CERTIFICATES) ?: error("Invalid update APK.")
        val current = pm.getPackageInfo(context.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        check(candidate.packageName == current.packageName && candidate.versionName == tag.removePrefix("v") &&
            candidate.longVersionCode > current.longVersionCode) { "APK version or application identity does not match." }
        val nextSigners = candidate.signingInfo?.apkContentsSigners?.toSet()
        val currentSigners = current.signingInfo?.apkContentsSigners?.toSet()
        check(!nextSigners.isNullOrEmpty() && nextSigners == currentSigners) {
            "This app uses a different signing key (for example a source/debug build). Keep this installation and update using the same key; do not uninstall to fix this."
        }
    }

    private fun runJob(text: String, manual: Boolean, work: () -> Result) {
        if (!gate.tryStart()) return
        action = null
        message = text
        notifyObservers()
        thread(name = "booxsend-update") {
            val result = try { work() } catch (error: Exception) {
                Result(if (manual) "Update failed: ${error.message}" else "Could not check for updates. Bluetooth transfers still work offline.")
            }
            handler.post {
                gate.finish()
                message = result.message
                action = result.action
                notifyObservers()
            }
        }
    }

    companion object {
        private const val MAX_DOWNLOAD_BYTES = 100 * 1024 * 1024L
        @Volatile private var instance: UpdateDownloads? = null
        fun get(context: Context): UpdateDownloads = instance ?: synchronized(this) {
            instance ?: UpdateDownloads(context.applicationContext).also { instance = it }
        }
        private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }
    }
}
