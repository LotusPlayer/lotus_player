package com.souljalazian.lotus_player

import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class LotusTagEditorController(
    private val context: Context,
    private val activityProvider: () -> Activity?
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_TAGS = "com.souljalazian.lotus_player/media_scanner"
        const val PENDING_INTENT_REQ_CODE = 4040
        private const val TAG = "LotusTagEditor"

        fun registerWith(
            messenger: BinaryMessenger,
            ctx: Context,
            provider: () -> Activity?
        ): LotusTagEditorController {
            val c = LotusTagEditorController(ctx.applicationContext, provider)
            MethodChannel(messenger, CHANNEL_TAGS).setMethodCallHandler(c)
            return c
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingResult: MethodChannel.Result? = null
    private var pendingArgs: Map<String, Any>? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scanFile" -> {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any> ?: emptyMap()
                val filePath = args["filePath"] as? String ?: ""
                if (filePath.isEmpty()) {
                    result.success(false)
                    return
                }
                try {
                    MediaScannerConnection.scanFile(
                        context,
                        arrayOf(filePath),
                        null
                    ) { _, uri ->
                        mainHandler.post {
                            try {
                                result.success(uri != null)
                            } catch (e: Exception) {
                                Log.w(TAG, "scanFile result delivery notice: ${e.message}")
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "scanFile error: ${e.message}")
                    result.success(false)
                }
            }

            "updateMediaStoreTags" -> {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any> ?: emptyMap()
                val filePath = args["filePath"] as? String ?: ""
                if (filePath.isEmpty()) {
                    result.error("INVALID_PATH", "File path is empty", null)
                    return
                }

                val file = File(filePath)
                if (!file.exists()) {
                    result.error("FILE_NOT_FOUND", "File does not exist: $filePath", null)
                    return
                }

                val uri = resolveMediaUri(args, filePath)

                // Android 11+ (API 30+) Scoped Storage: Request write approval from the user
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && uri != null) {
                    try {
                        val req = MediaStore.createWriteRequest(context.contentResolver, listOf(uri))
                        pendingResult?.let { oldRes ->
                            try {
                                oldRes.error("CANCELLED", "Superseded by a newer tag edit request", null)
                            } catch (_: Exception) {}
                        }
                        pendingResult = result
                        pendingArgs = args
                        val activity = activityProvider()
                        if (activity != null) {
                            activity.startIntentSenderForResult(
                                req.intentSender,
                                PENDING_INTENT_REQ_CODE,
                                null, 0, 0, 0, null
                            )
                            return
                        } else {
                            pendingResult = null
                            pendingArgs = null
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "createWriteRequest notice: ${e.message}")
                    }
                }

                doWrite(args, result)
            }

            else -> result.notImplemented()
        }
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != PENDING_INTENT_REQ_CODE) return false
        val res = pendingResult
        val args = pendingArgs
        pendingResult = null
        pendingArgs = null

        if (resultCode == Activity.RESULT_OK && args != null && res != null) {
            doWrite(args, res)
        } else {
            res?.error("PERMISSION_DENIED", "User denied file write approval", null)
        }
        return true
    }

    private fun resolveMediaUri(args: Map<String, Any>, filePath: String): Uri? {
        val songId = (args["songId"] as? Number)?.toLong() ?: 0L
        if (songId > 0) {
            return ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId)
        }

        try {
            val cursor = context.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.Audio.Media._ID),
                "${MediaStore.Audio.Media.DATA}=?",
                arrayOf(filePath),
                null
            )
            cursor?.use {
                if (it.moveToFirst()) {
                    val id = it.getLong(0)
                    return ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "resolveMediaUri query error: ${e.message}")
        }
        return null
    }

    private fun doWrite(args: Map<String, Any>, result: MethodChannel.Result) {
        Thread {
            try {
                val songIdStr = ((args["songId"] as? Number)?.toLong() ?: 0L)
                    .let { if (it > 0L) it.toString() else "" }
                val albumIdStr = ((args["albumId"] as? Number)?.toLong() ?: 0L)
                    .let { if (it > 0L) it.toString() else "" }
                val filePath = args["filePath"] as? String ?: ""
                val title = args["title"] as? String ?: ""
                val artist = args["artist"] as? String ?: ""
                val album = args["album"] as? String ?: ""
                val genre = args["genre"] as? String ?: ""
                val year = args["year"] as? String ?: ""
                val track = args["track"] as? String ?: ""
                val coverPath = args["coverPath"] as? String ?: ""
                val removeCover = args["removeCover"] as? Boolean ?: false

                val uri = resolveMediaUri(args, filePath)

                // Sync native artwork cache flags immediately
                if (songIdStr.isNotEmpty()) {
                    LotusBitmapLoader.markCoverRemoved(context, songIdStr, removeCover)
                    LotusBitmapLoader.invalidateTrackCache(
                        trackId = songIdStr,
                        albumId = albumIdStr.ifEmpty { null },
                        candidatePath = coverPath.ifEmpty { null }
                    )
                }

                // 1. Physical Write: Write ID3v2 header (Tags + Embedded Album Cover Art)
                if (filePath.endsWith(".mp3", ignoreCase = true)) {
                    try {
                        RandomAccessFile(File(filePath), "rw").use { raf ->
                            raf.channel.use { channel ->
                                val header = ByteBuffer.allocate(10)
                                while (header.hasRemaining()) {
                                    if (channel.read(header) == -1) break
                                }
                                header.flip()

                                val hasId3v2 = header.remaining() >= 10 &&
                                        header.get(0) == 'I'.code.toByte() &&
                                        header.get(1) == 'D'.code.toByte() &&
                                        header.get(2) == '3'.code.toByte()

                                val majorVersion = if (hasId3v2) (header.get(3).toInt() and 0xFF) else 0
                                var audioOffset = 0L
                                if (hasId3v2) {
                                    val s0 = header.get(6).toInt() and 0x7F
                                    val s1 = header.get(7).toInt() and 0x7F
                                    val s2 = header.get(8).toInt() and 0x7F
                                    val s3 = header.get(9).toInt() and 0x7F
                                    val tagSize = (s0 shl 21) or (s1 shl 14) or (s2 shl 7) or s3
                                    audioOffset = (10L + tagSize).coerceAtMost(channel.size())
                                }

                                // If user didn't pick a new cover and didn't delete the cover,
                                // preserve existing APIC frames so text-only edits don't lose cover art.
                                val preservedApicPayloads: List<ByteArray> =
                                    if (!removeCover && coverPath.isEmpty() && hasId3v2 && audioOffset > 10L) {
                                        extractExistingApicPayloads(channel, majorVersion, audioOffset)
                                    } else {
                                        emptyList()
                                    }

                                // Build ID3v2.3 UTF-8 frames
                                val frameOut = ByteArrayOutputStream()

                                fun writeTextFrame(id: String, text: String) {
                                    if (text.isEmpty()) return
                                    val tb = text.toByteArray(Charsets.UTF_8)
                                    val payloadSize = 1 + tb.size
                                    frameOut.write(id.toByteArray(Charsets.US_ASCII))
                                    frameOut.write((payloadSize shr 24) and 0xFF)
                                    frameOut.write((payloadSize shr 16) and 0xFF)
                                    frameOut.write((payloadSize shr 8) and 0xFF)
                                    frameOut.write(payloadSize and 0xFF)
                                    frameOut.write(0)
                                    frameOut.write(0)
                                    frameOut.write(3) // UTF-8 encoding flag
                                    frameOut.write(tb)
                                }

                                writeTextFrame("TIT2", title)
                                writeTextFrame("TPE1", artist)
                                writeTextFrame("TALB", album)
                                writeTextFrame("TCON", genre)
                                writeTextFrame("TYER", year)
                                writeTextFrame("TRCK", track)

                                if (!removeCover && coverPath.isNotEmpty()) {
                                    try {
                                        val coverFile = File(coverPath)
                                        if (coverFile.exists() && coverFile.length() > 0) {
                                            val imageBytes = coverFile.readBytes()
                                            val mime = if (coverPath.endsWith(".png", ignoreCase = true)) {
                                                "image/png"
                                            } else {
                                                "image/jpeg"
                                            }
                                            val mimeBytes = mime.toByteArray(Charsets.US_ASCII)
                                            val apicPayloadSize = 1 + mimeBytes.size + 1 + 1 + 1 + imageBytes.size

                                            frameOut.write("APIC".toByteArray(Charsets.US_ASCII))
                                            frameOut.write((apicPayloadSize shr 24) and 0xFF)
                                            frameOut.write((apicPayloadSize shr 16) and 0xFF)
                                            frameOut.write((apicPayloadSize shr 8) and 0xFF)
                                            frameOut.write(apicPayloadSize and 0xFF)
                                            frameOut.write(0)
                                            frameOut.write(0)
                                            frameOut.write(0) // ISO-8859-1 for MIME
                                            frameOut.write(mimeBytes)
                                            frameOut.write(0) // MIME null terminator
                                            frameOut.write(3) // Front Cover Art
                                            frameOut.write(0) // Description null terminator
                                            frameOut.write(imageBytes)
                                            Log.d(TAG, "Embedded APIC album artwork frame (${imageBytes.size} bytes)")
                                        }
                                    } catch (e: Exception) {
                                        Log.w(TAG, "APIC cover embedding error: ${e.message}")
                                    }
                                } else if (!removeCover && preservedApicPayloads.isNotEmpty()) {
                                    for (payload in preservedApicPayloads) {
                                        val sz = payload.size
                                        frameOut.write("APIC".toByteArray(Charsets.US_ASCII))
                                        frameOut.write((sz shr 24) and 0xFF)
                                        frameOut.write((sz shr 16) and 0xFF)
                                        frameOut.write((sz shr 8) and 0xFF)
                                        frameOut.write(sz and 0xFF)
                                        frameOut.write(0)
                                        frameOut.write(0)
                                        frameOut.write(payload)
                                    }
                                    Log.d(TAG, "Preserved ${preservedApicPayloads.size} existing APIC frame(s)")
                                } else if (removeCover) {
                                    Log.d(TAG, "Stripped APIC cover frame(s) from $filePath")
                                }

                                val frameBytes = frameOut.toByteArray()
                                channel.position(audioOffset)
                                val audioSize = (channel.size() - audioOffset).toInt().coerceAtLeast(0)
                                val audioBytes = ByteArray(audioSize)
                                val audioBuf = ByteBuffer.wrap(audioBytes)
                                while (audioBuf.hasRemaining()) {
                                    if (channel.read(audioBuf) == -1) break
                                }

                                if (frameBytes.isNotEmpty()) {
                                    val tagSize = frameBytes.size
                                    val newHeader = ByteArray(10)
                                    newHeader[0] = 'I'.code.toByte()
                                    newHeader[1] = 'D'.code.toByte()
                                    newHeader[2] = '3'.code.toByte()
                                    newHeader[3] = 3
                                    newHeader[4] = 0
                                    newHeader[5] = 0
                                    newHeader[6] = ((tagSize shr 21) and 0x7F).toByte()
                                    newHeader[7] = ((tagSize shr 14) and 0x7F).toByte()
                                    newHeader[8] = ((tagSize shr 7) and 0x7F).toByte()
                                    newHeader[9] = (tagSize and 0x7F).toByte()

                                    channel.position(0)
                                    writeFully(channel, ByteBuffer.wrap(newHeader))
                                    writeFully(channel, ByteBuffer.wrap(frameBytes))
                                    writeFully(channel, ByteBuffer.wrap(audioBytes))
                                    channel.truncate(10L + tagSize + audioBytes.size)
                                    channel.force(true)
                                    Log.d(TAG, "ID3v2 physical write completed for $filePath")
                                } else if (hasId3v2) {
                                    // All tags/cover cleared: strip ID3v2 header cleanly
                                    channel.position(0)
                                    writeFully(channel, ByteBuffer.wrap(audioBytes))
                                    channel.truncate(audioBytes.size.toLong())
                                    channel.force(true)
                                    Log.d(TAG, "Stripped empty ID3v2 tag for $filePath")
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "ID3v2 physical write notice: ${e.message}")
                    }
                }

                // 2. Direct MediaStore database commit
                if (uri != null) {
                    try {
                        val cv = ContentValues().apply {
                            if (title.isNotEmpty()) put(MediaStore.Audio.Media.TITLE, title)
                            if (artist.isNotEmpty()) put(MediaStore.Audio.Media.ARTIST, artist)
                            if (album.isNotEmpty()) put(MediaStore.Audio.Media.ALBUM, album)
                            if (year.isNotEmpty()) {
                                year.toIntOrNull()?.let { put(MediaStore.Audio.Media.YEAR, it) }
                            }
                            if (track.isNotEmpty()) {
                                track.toIntOrNull()?.let { put(MediaStore.Audio.Media.TRACK, it) }
                            }
                        }
                        if (cv.size() > 0) {
                            context.contentResolver.update(uri, cv, null, null)
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "MediaStore update notice: ${e.message}")
                    }
                }

                // 3. Scan file and wait briefly so MediaStore indexes updated/stripped art
                try {
                    val scanLatch = CountDownLatch(1)
                    MediaScannerConnection.scanFile(
                        context,
                        arrayOf(filePath),
                        null
                    ) { _, _ ->
                        scanLatch.countDown()
                    }
                    scanLatch.await(1500, TimeUnit.MILLISECONDS)
                } catch (_: Exception) {}

                mainHandler.post {
                    try {
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w(TAG, "Result delivery notice: ${e.message}")
                    }
                }
            } catch (e: Exception) {
                mainHandler.post {
                    try {
                        result.error("WRITE_FAILED", e.message, null)
                    } catch (err: Exception) {
                        Log.w(TAG, "Error delivery notice: ${err.message}")
                    }
                }
            }
        }.start()
    }

    private fun extractExistingApicPayloads(
        channel: FileChannel,
        majorVersion: Int,
        audioOffset: Long
    ): List<ByteArray> {
        if (majorVersion != 3 && majorVersion != 4) return emptyList()
        val apics = ArrayList<ByteArray>()
        try {
            var pos = 10L
            val fh = ByteArray(10)
            while (pos + 10L <= audioOffset) {
                channel.position(pos)
                val buf = ByteBuffer.wrap(fh)
                while (buf.hasRemaining()) {
                    if (channel.read(buf) == -1) return apics
                }
                if (fh[0].toInt() == 0 && fh[1].toInt() == 0 && fh[2].toInt() == 0 && fh[3].toInt() == 0) {
                    break // Padding reached
                }
                val frameId = String(fh, 0, 4, Charsets.US_ASCII)
                val frameSize = if (majorVersion == 4) {
                    ((fh[4].toInt() and 0x7F) shl 21) or
                            ((fh[5].toInt() and 0x7F) shl 14) or
                            ((fh[6].toInt() and 0x7F) shl 7) or
                            (fh[7].toInt() and 0x7F)
                } else {
                    ((fh[4].toInt() and 0xFF) shl 24) or
                            ((fh[5].toInt() and 0xFF) shl 16) or
                            ((fh[6].toInt() and 0xFF) shl 8) or
                            (fh[7].toInt() and 0xFF)
                }
                if (frameSize <= 0 || pos + 10L + frameSize > audioOffset) break

                if (frameId == "APIC" && frameSize <= 16 * 1024 * 1024) {
                    val payload = ByteArray(frameSize)
                    val pBuf = ByteBuffer.wrap(payload)
                    while (pBuf.hasRemaining()) {
                        if (channel.read(pBuf) == -1) break
                    }
                    apics.add(payload)
                }
                pos += 10L + frameSize
            }
        } catch (e: Exception) {
            Log.w(TAG, "extractExistingApicPayloads notice: ${e.message}")
        }
        return apics
    }

    private fun writeFully(channel: FileChannel, buffer: ByteBuffer) {
        while (buffer.hasRemaining()) {
            channel.write(buffer)
        }
    }
}