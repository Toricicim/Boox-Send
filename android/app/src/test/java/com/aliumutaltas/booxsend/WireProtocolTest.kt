package com.aliumutaltas.booxsend

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

class WireProtocolTest {
    @Test fun frameRoundTrip() {
        val output = ByteArrayOutputStream()
        FrameIO(ByteArrayInputStream(byteArrayOf()), output).write(FrameType.FILE_CHUNK, byteArrayOf(1, 2, 3))
        val frame = FrameIO(ByteArrayInputStream(output.toByteArray()), ByteArrayOutputStream()).read()
        assertEquals(FrameType.FILE_CHUNK, frame.type)
        assertArrayEquals(byteArrayOf(1, 2, 3), frame.payload)
    }

    @Test fun setupCodeProofIsCaseInsensitiveAndRejectsWrongProof() {
        val nonce = "nonce".toByteArray()
        val key = MessageDigest.getInstance("SHA-256").digest("AB12CD34".toByteArray())
        val proof = Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec(key, "HmacSHA256")); doFinal(nonce)
        }
        assertEquals("0uJFxA6IH4nZmsuD0uTfTlk47Yp+JZJsdWKkyPAbUaI=", Base64.getEncoder().encodeToString(proof))
        assertTrue(WireCrypto.authenticate("ab12cd34", Base64.getEncoder().encodeToString(nonce), Base64.getEncoder().encodeToString(proof)))
        assertFalse(WireCrypto.authenticate("wrong000", Base64.getEncoder().encodeToString(nonce), Base64.getEncoder().encodeToString(proof)))
    }
}
