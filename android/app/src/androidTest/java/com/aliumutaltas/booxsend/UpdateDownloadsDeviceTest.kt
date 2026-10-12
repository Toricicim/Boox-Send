package com.aliumutaltas.booxsend

import android.content.Context
import android.content.ContextWrapper
import androidx.core.content.FileProvider
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.File
import java.io.InputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** Device tests use isolated cache/preferences. Never install, clear or unpair the user's app. */
class UpdateDownloadsDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private lateinit var context: AuditContext
    private lateinit var fixture: File
    private lateinit var release: UpdateDownloads.Release

    private class AuditContext(base: Context) : ContextWrapper(base) {
        private val id = UUID.randomUUID().toString()
        private val folder = File(base.cacheDir, "updater-audit-$id").apply { mkdirs() }
        override fun getCacheDir(): File = folder
        override fun getSharedPreferences(name: String, mode: Int) =
            super.getSharedPreferences("updater-audit-$id-$name", mode)
        fun clean() { getSharedPreferences("updates", MODE_PRIVATE).edit().clear().commit(); folder.deleteRecursively() }
    }

    private class Source(private val file: File, var release: UpdateDownloads.Release) : UpdateSource {
        var lookups = 0
        var downloads = 0
        var failNetwork = false
        var delay: CountDownLatch? = null
        val downloadStarted = CountDownLatch(1)
        override fun latest(): UpdateDownloads.Release { lookups++; return release }
        override fun openDownload(url: String): InputStream {
            downloads++
            downloadStarted.countDown()
            delay?.let { check(it.await(10, TimeUnit.SECONDS)) }
            check(!failNetwork) { "Network unavailable" }
            return file.inputStream()
        }
    }

    @Before fun prepare() {
        context = AuditContext(instrumentation.targetContext.applicationContext)
        fixture = File(context.cacheDir, "candidate.apk")
        instrumentation.context.assets.open("updater-candidate.apk").use { input -> fixture.outputStream().use { input.copyTo(it) } }
        val info = context.packageManager.getPackageArchiveInfo(fixture.path, 0)!!
        val tag = "v${info.versionName}"
        val hash = MessageDigest.getInstance("SHA-256").digest(fixture.readBytes()).joinToString("") { "%02x".format(it) }
        release = UpdateDownloads.Release(tag, "https://github.com/Toricicim/Boox-Send/releases/download/$tag/BOOX-Send-android.apk", "sha256:$hash", fixture.length())
    }
    @After fun clean() { if (::context.isInitialized) context.clean() }

    private fun operation(repo: UpdateDownloads, start: () -> Unit): UpdateDownloads.State {
        val finished = CountDownLatch(1)
        val result = AtomicReference<UpdateDownloads.State>()
        var started = false
        val observer: (UpdateDownloads.State) -> Unit = {
            if (it.busy) started = true
            if (started && !it.busy) { result.set(it); finished.countDown() }
        }
        instrumentation.runOnMainSync { repo.observe(observer); start() }
        assertTrue("Update operation timed out", finished.await(15, TimeUnit.SECONDS))
        instrumentation.runOnMainSync { repo.removeObserver(observer) }
        return result.get()
    }

    @Test fun freshLookupsAndCachedInstallationSurviveObserverReplacement() {
        val source = Source(fixture, release)
        val repo = UpdateDownloads(context, source)
        operation(repo) { repo.check(manual = true) }
        assertEquals(1, source.lookups)
        instrumentation.runOnMainSync { assertTrue(repo.takeAction() is UpdateDownloads.Action.Offer) }

        source.delay = CountDownLatch(1)
        instrumentation.runOnMainSync { repo.download(release) }
        assertTrue(source.downloadStarted.await(5, TimeUnit.SECONDS))
        val completed = CountDownLatch(1)
        val replacement: (UpdateDownloads.State) -> Unit = { if (!it.busy && it.ready) completed.countDown() }
        instrumentation.runOnMainSync {
            repo.observe(replacement)
            repo.check(manual = true) // A newly resumed screen must not start competing work.
        }
        assertEquals(1, source.lookups)
        source.delay!!.countDown()
        assertTrue(completed.await(15, TimeUnit.SECONDS))
        instrumentation.runOnMainSync { repo.removeObserver(replacement); assertTrue(repo.takeAction() is UpdateDownloads.Action.Install) }
        assertEquals(1, source.downloads)

        source.failNetwork = true
        assertTrue(operation(repo) { repo.prepareInstall() }.ready)
        assertEquals("Cached APK should not be downloaded again", 1, source.downloads)
        instrumentation.runOnMainSync { repo.takeAction() }
        source.release = release.copy(tag = "v9.0.0", url = release.url.replace(release.tag, "v9.0.0"))
        operation(repo) { repo.check(manual = true) }
        assertEquals(2, source.lookups)
        instrumentation.runOnMainSync {
            assertEquals("v9.0.0", (repo.takeAction() as UpdateDownloads.Action.Offer).release.tag)
        }
    }

    @Test fun corruptedCacheIsRejectedAndCanBeDownloadedAgain() {
        val source = Source(fixture, release)
        val repo = UpdateDownloads(context, source)
        assertTrue(operation(repo) { repo.download(release) }.ready)
        instrumentation.runOnMainSync { repo.takeAction() }
        repo.apk.appendBytes(byteArrayOf(1))
        val rejected = operation(repo) { repo.prepareInstall() }
        assertFalse(rejected.ready)
        assertTrue(rejected.message.contains("checksum"))
        assertTrue(operation(repo) { repo.download(release) }.ready)
        assertEquals(2, source.downloads)
        instrumentation.runOnMainSync { repo.takeAction() }
    }

    @Test fun wrongDigestIsRejectedAndFileProviderServesOnlyTheScopedProbe() {
        val source = Source(fixture, release)
        val repo = UpdateDownloads(context, source)
        val bad = release.copy(digest = "sha256:" + "0".repeat(64))
        val rejected = operation(repo) { repo.download(bad) }
        assertFalse(rejected.ready)
        assertTrue(rejected.message.contains("checksum"))
        val actual = instrumentation.targetContext
        val probe = File(actual.cacheDir, "updates/provider-audit-${UUID.randomUUID()}.apk")
        probe.parentFile!!.mkdirs()
        try {
            probe.writeBytes(byteArrayOf(1, 2, 3))
            val uri = FileProvider.getUriForFile(actual, "${actual.packageName}.updates", probe)
            assertArrayEquals(byteArrayOf(1, 2, 3), actual.contentResolver.openInputStream(uri)!!.use { it.readBytes() })
        } finally { probe.delete() }
    }
}
