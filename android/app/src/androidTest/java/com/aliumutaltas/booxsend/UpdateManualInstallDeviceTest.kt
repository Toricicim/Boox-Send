package com.aliumutaltas.booxsend

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Explicit opt-in test: stage a same-key candidate for user-approved installer testing. */
class UpdateManualInstallDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private fun fixture() = instrumentation.context.assets.open("updater-candidate.apk").use { it.readBytes() }
    private fun hash(bytes: ByteArray) = "sha256:" + MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    @Test fun stageCandidate() {
        val bytes = fixture()
        val context = instrumentation.targetContext.applicationContext
        val probe = java.io.File(context.cacheDir, "updater-fixture-version.apk")
        val tag = try {
            probe.writeBytes(bytes)
            "v${context.packageManager.getPackageArchiveInfo(probe.path, 0)!!.versionName}"
        } finally { probe.delete() }
        val release = UpdateDownloads.Release(tag, "https://github.com/Toricicim/Boox-Send/releases/download/$tag/BOOX-Send-android.apk", hash(bytes), bytes.size.toLong())
        val source = object : UpdateSource {
            override fun latest() = release
            override fun openDownload(url: String) = bytes.inputStream()
        }
        val repo = UpdateDownloads(context, source)
        val done = CountDownLatch(1)
        var started = false
        var success = false
        val observer: (UpdateDownloads.State) -> Unit = {
            if (it.busy) started = true
            if (started && !it.busy) { success = it.ready; done.countDown() }
        }
        instrumentation.runOnMainSync { repo.observe(observer); repo.download(release) }
        assertTrue(done.await(15, TimeUnit.SECONDS))
        instrumentation.runOnMainSync { repo.removeObserver(observer); repo.takeAction() }
        assertTrue("Candidate was not verified and cached", success)
    }

    @Test fun removeStagedCandidate() {
        val context = instrumentation.targetContext.applicationContext
        val prefs = context.getSharedPreferences("updates", android.content.Context.MODE_PRIVATE)
        if (prefs.getString("readyDigest", "") == hash(fixture())) {
            val apk = java.io.File(context.cacheDir, "updates/BOOX-Send-android.apk")
            if (apk.exists()) assertTrue(apk.delete())
            assertTrue(prefs.edit().remove("readyTag").remove("readyDigest").remove("waitingForInstallPermission").commit())
        }
    }
}
