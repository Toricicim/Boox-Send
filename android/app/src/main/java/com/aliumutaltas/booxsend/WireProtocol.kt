package com.aliumutaltas.booxsend

import org.json.JSONObject
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.Base64
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

enum class FrameType(val id: Int) {
    HELLO(1), HELLO_ACK(2), FILE_OFFER(3), FILE_DECISION(4), FILE_CHUNK(5),
    FILE_COMMIT(6), FILE_RESULT(7), FINISH(8);

    companion object { fun from(id: Int) = entries.firstOrNull { it.id == id } }
}

data class WireFrame(val type: FrameType, val payload: ByteArray)

class FrameIO(input: InputStream, output: OutputStream) {
    private val input = DataInputStream(input)
    private val output = DataOutputStream(output)

    fun read(): WireFrame {
        val length = try { input.readInt() } catch (e: EOFException) { throw e }
        require(length in 1..1_048_576) { "Invalid frame length" }
        val type = FrameType.from(input.readUnsignedByte()) ?: error("Unknown frame type")
        val payload = ByteArray(length - 1)
        input.readFully(payload)
        return WireFrame(type, payload)
    }

    @Synchronized
    fun write(type: FrameType, payload: ByteArray = byteArrayOf()) {
        output.writeInt(payload.size + 1)
        output.writeByte(type.id)
        output.write(payload)
        output.flush()
    }

    fun writeJson(type: FrameType, json: JSONObject) = write(type, json.toString().toByteArray(Charsets.UTF_8))
}

object WireCrypto {
    fun authenticate(setupCode: String, nonceBase64: String, proofBase64: String): Boolean {
        val nonce = Base64.getDecoder().decode(nonceBase64)
        val key = MessageDigest.getInstance("SHA-256").digest(setupCode.uppercase().toByteArray(Charsets.UTF_8))
        val mac = Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(key, "HmacSHA256")) }
        val expected = mac.doFinal(nonce)
        val actual = try { Base64.getDecoder().decode(proofBase64) } catch (_: IllegalArgumentException) { return false }
        return MessageDigest.isEqual(expected, actual)
    }

    fun uuid(bytes: ByteArray, offset: Int = 0): UUID {
        val buffer = ByteBuffer.wrap(bytes, offset, 16)
        return UUID(buffer.long, buffer.long)
    }

    fun uint64(bytes: ByteArray, offset: Int): Long = ByteBuffer.wrap(bytes, offset, 8).long
}
