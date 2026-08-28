package com.aliumutaltas.booxsend

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID

class TransferSession(context: Context, input: InputStream, output: OutputStream) {
    private val prefs = context.getSharedPreferences(Constants.PREFS, Context.MODE_PRIVATE)
    private val frames = FrameIO(input, output)
    private val storage = TransferStorage(context)
    private val reservations = mutableMapOf<UUID, Reservation>()

    fun run() {
        try {
            authenticate()
            while (true) {
                val frame = frames.read()
                when (frame.type) {
                    FrameType.FILE_OFFER -> offer(frame.payload)
                    FrameType.FILE_CHUNK -> chunk(frame.payload)
                    FrameType.FILE_COMMIT -> commit(frame.payload)
                    FrameType.FINISH -> return
                    else -> error("Unexpected ${frame.type}")
                }
            }
        } finally {
            storage.close()
        }
    }

    private fun authenticate() {
        val frame = frames.read()
        require(frame.type == FrameType.HELLO) { "HELLO required" }
        val hello = JSONObject(frame.payload.toString(Charsets.UTF_8))
        val setupCode = prefs.getString(Constants.KEY_SETUP_CODE, "") ?: ""
        val accepted = hello.optInt("version") == Constants.PROTOCOL_VERSION && setupCode.isNotBlank() &&
            WireCrypto.authenticate(setupCode, hello.getString("nonce"), hello.getString("proof"))
        frames.writeJson(FrameType.HELLO_ACK, JSONObject().put("accepted", accepted).put("message", if (accepted) JSONObject.NULL else "Authentication failed"))
        require(accepted) { "Authentication failed" }
    }

    private fun offer(payload: ByteArray) {
        val json = JSONObject(payload.toString(Charsets.UTF_8))
        val offer = IncomingOffer(
            id = UUID.fromString(json.getString("transferId")),
            name = json.getString("name"),
            size = json.getLong("size"),
            sha256 = json.getString("sha256").lowercase()
        )
        val response = try {
            require(offer.size >= 0) { "Invalid size" }
            val reservation = storage.reserve(offer)
            reservations[offer.id] = reservation
            JSONObject().put("transferId", offer.id.toString()).put("accepted", true)
                .put("destinationName", reservation.destinationName).put("resumeOffset", reservation.offset)
                .put("message", JSONObject.NULL)
        } catch (error: Exception) {
            JSONObject().put("transferId", offer.id.toString()).put("accepted", false)
                .put("destinationName", JSONObject.NULL).put("resumeOffset", 0)
                .put("message", error.message ?: "File rejected")
        }
        frames.writeJson(FrameType.FILE_DECISION, response)
    }

    private fun chunk(payload: ByteArray) {
        require(payload.size >= 24) { "Invalid chunk" }
        val id = WireCrypto.uuid(payload)
        val offset = WireCrypto.uint64(payload, 16)
        require(offset >= 0) { "Invalid offset" }
        val reservation = reservations[id] ?: error("Unknown transfer")
        storage.append(reservation, offset, payload.copyOfRange(24, payload.size))
    }

    private fun commit(payload: ByteArray) {
        val json = JSONObject(payload.toString(Charsets.UTF_8))
        val id = UUID.fromString(json.getString("transferId"))
        val response = try {
            val reservation = reservations[id] ?: error("Unknown transfer")
            val destination = storage.commit(reservation)
            JSONObject().put("transferId", id.toString()).put("success", true).put("message", destination)
        } catch (error: Exception) {
            Log.e("BooxSend", "Commit failed", error)
            storage.reset(id)
            reservations.remove(id)
            JSONObject().put("transferId", id.toString()).put("success", false).put("message", error.message ?: "Commit failed")
        }
        frames.writeJson(FrameType.FILE_RESULT, response)
    }
}
