package com.aliumutaltas.booxsend

import org.json.JSONObject
import java.io.FilterInputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

internal interface UpdateSource {
    fun latest(): UpdateDownloads.Release
    fun openDownload(url: String): InputStream
}

internal object GitHubUpdateSource : UpdateSource {
    override fun latest(): UpdateDownloads.Release {
        val conn = connection("https://api.github.com/repos/Toricicim/Boox-Send/releases/latest", metadata = true)
        try {
            val json = conn.inputStream.bufferedReader().use { JSONObject(it.readText()) }
            check(!json.getBoolean("draft") && !json.getBoolean("prerelease")) { "No stable release available." }
            val tag = json.getString("tag_name")
            check(UpdatePolicy.version(tag) != null) { "Invalid release version." }
            val assets = json.getJSONArray("assets")
            val asset = (0 until assets.length()).map { assets.getJSONObject(it) }
                .firstOrNull { it.getString("name") == "BOOX-Send-android.apk" }
            return UpdateDownloads.Release(tag, asset?.optString("browser_download_url").orEmpty(),
                asset?.optString("digest").orEmpty(), asset?.optLong("size") ?: 0)
        } finally { conn.disconnect() }
    }

    override fun openDownload(url: String): InputStream {
        val conn = connection(url)
        try {
            return object : FilterInputStream(conn.inputStream) {
                override fun close() { try { super.close() } finally { conn.disconnect() } }
            }
        } catch (error: Exception) { conn.disconnect(); throw error }
    }

    private fun connection(url: String, metadata: Boolean = false): HttpURLConnection {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 15000
        conn.readTimeout = 30000
        conn.useCaches = false
        conn.setRequestProperty("User-Agent", "BOOX-Send-Updater")
        if (metadata) {
            conn.setRequestProperty("Accept", "application/vnd.github+json")
            conn.setRequestProperty("Cache-Control", "no-cache")
        }
        try {
            check(conn.responseCode in 200..299) { "Server returned ${conn.responseCode}." }
            check(conn.url.protocol == "https") { "Update requires HTTPS." }
            return conn
        } catch (error: Exception) { conn.disconnect(); throw error }
    }
}
