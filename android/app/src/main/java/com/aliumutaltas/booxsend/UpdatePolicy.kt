package com.aliumutaltas.booxsend

import java.net.URI

object UpdatePolicy {
    fun version(value: String): List<Int>? {
        val match = Regex("^v?(\\d+)\\.(\\d+)\\.(\\d+)$").matchEntire(value) ?: return null
        return match.groupValues.drop(1).map { it.toIntOrNull() ?: return null }
    }

    fun isNewer(candidate: String, installed: String): Boolean {
        val next = version(candidate) ?: return false
        val current = version(installed) ?: return false
        for (i in next.indices) {
            if (next[i] != current[i]) return next[i] > current[i]
        }
        return false
    }

    fun validAsset(url: String, digest: String): Boolean {
        val uri = runCatching { URI(url) }.getOrNull() ?: return false
        return uri.scheme == "https" && uri.host == "github.com" && uri.port == -1 &&
            uri.userInfo == null && uri.query == null && uri.fragment == null &&
            Regex("^/Toricicim/Boox-Send/releases/download/v\\d+\\.\\d+\\.\\d+/BOOX-Send-android\\.apk$").matches(uri.path) &&
            Regex("^sha256:[0-9a-f]{64}$").matches(digest)
    }
}
