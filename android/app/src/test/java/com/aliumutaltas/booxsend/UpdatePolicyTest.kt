package com.aliumutaltas.booxsend

import org.junit.Assert.*
import org.junit.Test

class UpdatePolicyTest {
    @Test fun versionsAreComparedNumericallyAndDowngradesAreRejected() {
        assertTrue(UpdatePolicy.isNewer("v1.0.10", "1.0.9"))
        assertFalse(UpdatePolicy.isNewer("v1.0.6", "1.0.6"))
        assertFalse(UpdatePolicy.isNewer("v1.0.5", "1.0.6"))
        assertFalse(UpdatePolicy.isNewer("v1.0.7-beta", "1.0.6"))
        assertFalse(UpdatePolicy.isNewer("v99999999999.0.1", "1.0.6"))
    }

    @Test fun onlyOfficialReleaseAssetsWithChecksumsAreAccepted() {
        val url = "https://github.com/Toricicim/Boox-Send/releases/download/v1.0.6/BOOX-Send-android.apk"
        val digest = "sha256:" + "a".repeat(64)
        assertTrue(UpdatePolicy.validAsset(url, digest))
        assertFalse(UpdatePolicy.validAsset(url.replace("https", "http"), digest))
        assertFalse(UpdatePolicy.validAsset(url.replace("github.com", "github.com.evil.test"), digest))
        assertFalse(UpdatePolicy.validAsset(url.replace("Toricicim", "other"), digest))
        assertFalse(UpdatePolicy.validAsset(url, ""))
    }
}
