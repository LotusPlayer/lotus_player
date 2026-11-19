package com.souljalazian.lotus_player

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import androidx.core.graphics.scale
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import kotlin.math.min
import kotlin.math.roundToInt

class ArtworkCachePlugin : FlutterPlugin, MethodCallHandler {

    companion object {
        private const val TAG = "ArtworkCachePlugin"
        private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
    }

    private var channel: MethodChannel? = null
    private lateinit var context: Context
    private val mainHandler = Handler(Looper.getMainLooper())
    private var executor: ExecutorService? = null

    @Volatile
    private var isDetached: Boolean = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        isDetached = false
        executor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "ArtworkCacheWorker").apply { isDaemon = true }
        }
        channel = MethodChannel(
            binding.binaryMessenger,
            "com.souljalazian.lotus_player/artwork_cache"
        ).apply {
            setMethodCallHandler(this@ArtworkCachePlugin)
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method != "getArtwork") {
            result.notImplemented()
            return
        }

        if (isDetached) {
            result.success(null)
            return
        }

        val songId = (call.argument<Any>("songId") as? Number)?.toLong()
        if (songId == null || songId <= 0L) {
            result.error("INVALID_ID", "songId is required", null)
            return
        }
        val width = ((call.argument<Any>("width") as? Number)?.toInt() ?: 256).coerceAtLeast(1)
        val height = ((call.argument<Any>("height") as? Number)?.toInt() ?: 256).coerceAtLeast(1)

        val worker = executor
        if (worker == null || worker.isShutdown) {
            result.success(null)
            return
        }

        try {
            worker.execute {
                val bytes = if (isDetached) {
                    null
                } else {
                    try {
                        getArtworkBytes(songId, width, height)
                    } catch (e: Exception) {
                        Log.w(TAG, "Artwork load failed for song $songId: ${e.message}")
                        null
                    }
                }
                mainHandler.post {
                    if (!isDetached) {
                        try {
                            result.success(bytes)
                        } catch (e: Exception) {
                            Log.w(TAG, "Result delivery notice: ${e.message}")
                        }
                    }
                }
            }
        } catch (e: RejectedExecutionException) {
            Log.w(TAG, "Artwork worker rejected task: ${e.message}")
            result.success(null)
        }
    }

    private fun getArtworkBytes(songId: Long, targetWidth: Int, targetHeight: Int): ByteArray? {
        val prefs = context.getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)

        // 1. Respect explicit cover deletion immediately across all audio formats
        val isCoverRemoved = prefs.getBoolean("flutter.tag_override_${songId}_cover_removed", false)
        if (isCoverRemoved) {
            return null
        }

        // 2. Check custom gallery cover override first (supports FLAC/M4A/WAV + instant MP3)
        val customCoverPath = prefs.getString("flutter.tag_override_${songId}_cover_path", null)
        if (!customCoverPath.isNullOrEmpty()) {
            val coverFile = File(customCoverPath)
            if (coverFile.exists() && coverFile.length() > 0L) {
                decodeAndScale(coverFile.readBytes(), targetWidth, targetHeight)?.let { return it }
            }
        }

        // 3. Fallback to physical audio file embedded artwork via MediaMetadataRetriever
        var retriever: MediaMetadataRetriever? = null
        try {
            retriever = MediaMetadataRetriever()
            val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId)
            retriever.setDataSource(context, uri)
            val art = retriever.embeddedPicture ?: return null
            return decodeAndScale(art, targetWidth, targetHeight)
        } catch (e: Exception) {
            Log.w(TAG, "getArtworkBytes failed for $songId: ${e.message}")
            return null
        } finally {
            try {
                retriever?.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun decodeAndScale(rawBytes: ByteArray, targetWidth: Int, targetHeight: Int): ByteArray? {
        val options = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeByteArray(rawBytes, 0, rawBytes.size, options)
        if (options.outWidth <= 0 || options.outHeight <= 0) return null

        options.inSampleSize = calculateInSampleSize(options, targetWidth, targetHeight)
        options.inJustDecodeBounds = false

        val bitmap = BitmapFactory.decodeByteArray(rawBytes, 0, rawBytes.size, options) ?: return null

        val scaled = if (bitmap.width <= targetWidth && bitmap.height <= targetHeight) {
            bitmap
        } else {
            val ratio = min(
                targetWidth.toFloat() / bitmap.width.toFloat(),
                targetHeight.toFloat() / bitmap.height.toFloat()
            )
            val destWidth = (bitmap.width * ratio).roundToInt().coerceAtLeast(1)
            val destHeight = (bitmap.height * ratio).roundToInt().coerceAtLeast(1)
            val s = bitmap.scale(destWidth, destHeight)
            if (s !== bitmap) bitmap.recycle()
            s
        }

        val output = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, 82, output)
        val bytes = output.toByteArray()
        scaled.recycle()

        return bytes
    }

    private fun calculateInSampleSize(options: BitmapFactory.Options, reqWidth: Int, reqHeight: Int): Int {
        val height = options.outHeight
        val width = options.outWidth
        var inSampleSize = 1

        if (height > reqHeight || width > reqWidth) {
            val halfHeight = height / 2
            val halfWidth = width / 2

            while (halfHeight / inSampleSize >= reqHeight && halfWidth / inSampleSize >= reqWidth) {
                inSampleSize *= 2
            }
        }
        return inSampleSize
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        isDetached = true
        channel?.setMethodCallHandler(null)
        channel = null
        executor?.shutdown()
        executor = null
    }
}