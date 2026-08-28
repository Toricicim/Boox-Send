package com.aliumutaltas.booxsend

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.documentfile.provider.DocumentFile
import org.json.JSONObject
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.security.MessageDigest
import java.util.UUID
import android.webkit.MimeTypeMap

data class IncomingOffer(val id: UUID, val name: String, val size: Long, val sha256: String)
data class Reservation(val offer: IncomingOffer, val partUri: Uri?, val destinationName: String, val offset: Long, val completed: Boolean)

class TransferStorage(private val context: Context) : AutoCloseable {
    private data class OpenWriter(
        val stream: FileOutputStream,
        val channel: FileChannel,
        var offset: Long,
    )

    private val prefs = context.getSharedPreferences(Constants.PREFS, Context.MODE_PRIVATE)
    private val writers = mutableMapOf<UUID, OpenWriter>()
    private val root: DocumentFile
        get() {
            val value = prefs.getString(Constants.KEY_TREE_URI, null) ?: error("Destination folder is not configured")
            return DocumentFile.fromTreeUri(context, Uri.parse(value)) ?: error("Destination folder is unavailable")
        }

    init { pruneOldRecords() }

    fun reserve(offer: IncomingOffer): Reservation {
        record(offer.id)?.let { existing ->
            if (existing.optString("sha256") == offer.sha256 && existing.optLong("size") == offer.size) {
                val completed = existing.optBoolean("completed")
                val partUri = existing.optString("partUri").takeIf { it.isNotBlank() }?.let(Uri::parse)
                if (completed) return Reservation(offer, null, existing.getString("destinationName"), offer.size, true)
                if (partUri != null && DocumentFile.fromSingleUri(context, partUri)?.exists() == true) {
                    val offset = documentLength(partUri)
                    return Reservation(offer, partUri, existing.getString("destinationName"), offset.coerceAtMost(offer.size), false)
                }
                removeRecord(offer.id)
            }
            reset(offer.id)
        }

        val destination = uniqueName(sanitizeName(offer.name))
        val partName = ".booxsend-${offer.id}.part"
        root.findFile(partName)?.delete()
        val part = root.createFile("application/octet-stream", partName)
            ?: error("Could not create partial document")
        val json = JSONObject()
            .put("partUri", part.uri.toString())
            .put("destinationName", destination)
            .put("size", offer.size)
            .put("sha256", offer.sha256)
            .put("completed", false)
            .put("updatedAt", System.currentTimeMillis())
        saveRecord(offer.id, json)
        return Reservation(offer, part.uri, destination, 0, false)
    }

    fun append(reservation: Reservation, offset: Long, bytes: ByteArray) {
        require(!reservation.completed) { "Transfer is already completed" }
        require(offset >= 0 && offset + bytes.size <= reservation.offer.size) { "Chunk exceeds file size" }
        val uri = reservation.partUri ?: error("Partial document is missing")
        val writer = writers.getOrPut(reservation.offer.id) {
            val current = documentLength(uri)
            val descriptor = context.contentResolver.openFileDescriptor(uri, "rw")
                ?: error("Could not open partial document")
            val stream = ParcelFileDescriptor.AutoCloseOutputStream(descriptor)
            val channel = stream.channel
            channel.position(current)
            OpenWriter(stream, channel, current)
        }
        require(writer.offset == offset) { "Non-contiguous chunk: expected ${writer.offset}, got $offset" }
        val buffer = ByteBuffer.wrap(bytes)
        while (buffer.hasRemaining()) writer.channel.write(buffer)
        writer.offset += bytes.size
    }

    fun commit(reservation: Reservation): String {
        if (reservation.completed) return reservation.destinationName
        val uri = reservation.partUri ?: error("Partial document is missing")
        closeWriter(reservation.offer.id)
        require(documentLength(uri) == reservation.offer.size) { "Received size does not match offer" }
        require(sha256(uri) == reservation.offer.sha256.lowercase()) { "SHA-256 verification failed" }

        val part = DocumentFile.fromSingleUri(context, uri) ?: error("Partial document disappeared")
        val finalName = if (nameExists(reservation.destinationName)) uniqueName(reservation.destinationName) else reservation.destinationName
        if (!runCatching { part.renameTo(finalName) }.getOrDefault(false)) {
            // Some BOOX document providers can create and write files but do
            // not implement DocumentsContract.renameDocument. Fall back to a
            // verified copy before removing the partial document.
            val extension = finalName.substringAfterLast('.', "").lowercase()
            val mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
                ?: "application/octet-stream"
            val destination = root.createFile(mimeType, finalName)
                ?: error("Could not create destination document")
            try {
                context.contentResolver.openInputStream(uri)!!.use { input ->
                    context.contentResolver.openOutputStream(destination.uri, "wt")!!.use { output ->
                        input.copyTo(output, 1024 * 1024)
                    }
                }
                require(destination.length() == reservation.offer.size) { "Final copy size verification failed" }
                require(sha256(destination.uri) == reservation.offer.sha256.lowercase()) { "Final copy verification failed" }
                require(part.delete()) { "Could not remove partial document" }
            } catch (error: Exception) {
                destination.delete()
                throw error
            }
        }
        val json = record(reservation.offer.id) ?: JSONObject()
        json.put("completed", true)
            .put("destinationName", finalName)
            .put("partUri", "")
            .put("updatedAt", System.currentTimeMillis())
        saveRecord(reservation.offer.id, json)
        return finalName
    }

    fun reset(id: UUID) {
        closeWriter(id)
        record(id)?.optString("partUri")?.takeIf { it.isNotBlank() }?.let { value ->
            runCatching { DocumentFile.fromSingleUri(context, Uri.parse(value))?.delete() }
        }
        removeRecord(id)
    }

    private fun sanitizeName(input: String): String {
        val basename = input.substringAfterLast('/').substringAfterLast('\\')
            .replace(Regex("[\\u0000-\\u001F]"), "_").trim()
        return basename.ifBlank { "file" }.take(240)
    }

    private fun uniqueName(requested: String): String {
        if (!nameExists(requested)) return requested
        val dot = requested.lastIndexOf('.')
        val stem = if (dot > 0) requested.substring(0, dot) else requested
        val ext = if (dot > 0) requested.substring(dot) else ""
        var index = 1
        while (true) {
            val candidate = "$stem ($index)$ext"
            if (!nameExists(candidate)) return candidate
            index++
        }
    }

    private fun nameExists(name: String): Boolean = root.listFiles().any { it.name.equals(name, ignoreCase = true) }
    private fun documentLength(uri: Uri): Long = DocumentFile.fromSingleUri(context, uri)?.length() ?: 0L

    private fun sha256(uri: Uri): String {
        val digest = MessageDigest.getInstance("SHA-256")
        context.contentResolver.openFileDescriptor(uri, "r")!!.use { descriptor ->
            FileInputStream(descriptor.fileDescriptor).use { input ->
                val buffer = ByteArray(1024 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (count > 0) digest.update(buffer, 0, count)
                }
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun record(id: UUID): JSONObject? = prefs.getString("transfer_$id", null)?.let(::JSONObject)
    private fun saveRecord(id: UUID, value: JSONObject) { prefs.edit().putString("transfer_$id", value.toString()).apply() }
    private fun removeRecord(id: UUID) { prefs.edit().remove("transfer_$id").apply() }
    private fun touch(id: UUID) { record(id)?.also { it.put("updatedAt", System.currentTimeMillis()); saveRecord(id, it) } }

    private fun closeWriter(id: UUID) {
        writers.remove(id)?.let { writer ->
            runCatching { writer.channel.force(false) }
            runCatching { writer.stream.close() }
            touch(id)
        }
    }

    override fun close() {
        writers.keys.toList().forEach(::closeWriter)
    }

    private fun pruneOldRecords() {
        val cutoff = System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1000
        prefs.all.filterKeys { it.startsWith("transfer_") }.forEach { (key, value) ->
            val json = runCatching { JSONObject(value as String) }.getOrNull() ?: return@forEach
            if (json.optLong("updatedAt") < cutoff) {
                json.optString("partUri").takeIf { it.isNotBlank() }?.let { uri ->
                    runCatching { DocumentFile.fromSingleUri(context, Uri.parse(uri))?.delete() }
                }
                prefs.edit().remove(key).apply()
            }
        }
    }
}
