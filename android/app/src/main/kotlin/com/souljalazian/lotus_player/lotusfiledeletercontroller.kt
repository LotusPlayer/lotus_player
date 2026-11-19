package com.souljalazian.lotus_player

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.Context
import android.content.Intent
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
import java.io.File

class LotusFileDeleterController(
    private val context: Context,
    @Volatile private var activityProvider: () -> Activity?
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "LotusFileDeleter"
        const val CHANNEL_DELETER = "com.souljalazian.lotus_player/media_storage_deleter"
        const val DELETE_INTENT_REQ_CODE = 4041

        @Volatile
        private var instance: LotusFileDeleterController? = null
        private var channel: MethodChannel? = null

        fun registerWith(
            messenger: BinaryMessenger,
            context: Context,
            activityProvider: () -> Activity?
        ): LotusFileDeleterController {
            val controller = instance ?: synchronized(this) {
                instance ?: LotusFileDeleterController(context.applicationContext, activityProvider).also {
                    instance = it
                }
            }
            controller.activityProvider = activityProvider
            channel?.setMethodCallHandler(null)
            channel = MethodChannel(messenger, CHANNEL_DELETER).apply {
                setMethodCallHandler(controller)
            }
            return controller
        }

        @Suppress("unused")
        fun detach() {
            channel?.setMethodCallHandler(null)
            channel = null
            instance?.resetPendingState()
            instance = null
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingResult: MethodChannel.Result? = null
    private var pendingUris: List<Uri> = emptyList()
    private var pendingFilePaths: List<String> = emptyList()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "deletePhysicalAudioFile" -> {
                if (pendingResult != null) {
                    result.error("BUSY", "Another file deletion is in progress.", null)
                    return
                }

                val filePath = call.argument<String>("filePath") ?: ""
                val songId = (call.argument<Number>("songId"))?.toLong() ?: -1L

                if (filePath.isEmpty() && songId <= 0) {
                    result.error("INVALID_ARGS", "filePath and songId are both empty", null)
                    return
                }

                val itemUri = if (songId > 0) {
                    ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId)
                } else {
                    findUriFromPath(filePath)
                }

                if (itemUri == null && filePath.isEmpty()) {
                    result.error("NOT_FOUND", "Could not resolve media uri for track", null)
                    return
                }

                pendingResult = result
                pendingFilePaths = if (filePath.isNotEmpty()) listOf(filePath) else emptyList()
                pendingUris = if (itemUri != null) listOf(itemUri) else emptyList()

                executeDeletionWithSystemDialog(pendingUris, pendingFilePaths)
            }

            "deletePhysicalAudioFilesBatch" -> {
                if (pendingResult != null) {
                    result.error("BUSY", "Another file deletion is in progress.", null)
                    return
                }

                val filePaths = call.argument<List<String>>("filePaths") ?: emptyList()
                val songIds = call.argument<List<Number>>("songIds")?.map { it.toLong() } ?: emptyList()

                if (filePaths.isEmpty() && songIds.none { it > 0 }) {
                    result.error("INVALID_ARGS", "filePaths and songIds are both empty", null)
                    return
                }

                val uris = mutableListOf<Uri>()
                for (id in songIds) {
                    if (id > 0) {
                        uris.add(ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id))
                    }
                }
                if (uris.isEmpty()) {
                    for (path in filePaths) {
                        if (path.isNotEmpty()) {
                            findUriFromPath(path)?.let { uris.add(it) }
                        }
                    }
                }

                pendingResult = result
                pendingFilePaths = filePaths
                pendingUris = uris

                executeDeletionWithSystemDialog(pendingUris, pendingFilePaths)
            }

            else -> result.notImplemented()
        }
    }

    private fun executeDeletionWithSystemDialog(uris: List<Uri>, filePaths: List<String>) {
        val activity = activityProvider()
        if (activity == null || activity.isFinishing || activity.isDestroyed) {
            // Direct delete fallback if activity context is unavailable
            val allOk = deleteDirectFallback(uris, filePaths)
            finishWithSuccess(allOk, filePaths)
            return
        }

        activity.runOnUiThread {
            try {
                val resolver = context.contentResolver

                // Android 11+ (API 30-35) - Single System Confirmation Dialog via Scoped Storage
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && uris.isNotEmpty()) {
                    try {
                        val pendingIntent = MediaStore.createDeleteRequest(resolver, uris)
                        activity.startIntentSenderForResult(
                            pendingIntent.intentSender,
                            DELETE_INTENT_REQ_CODE,
                            null, 0, 0, 0, null
                        )
                        Log.d(TAG, "Launched Scoped Storage delete dialog for ${uris.size} track(s)")
                        return@runOnUiThread
                    } catch (e: Exception) {
                        Log.w(TAG, "createDeleteRequest failed, attempting fallback: ${e.message}")
                    }
                }

                // Android 10 (API 29) - RecoverableSecurityException handling
                if (uris.isNotEmpty()) {
                    try {
                        var deletedCount = 0
                        for (uri in uris) {
                            val rows = resolver.delete(uri, null, null)
                            if (rows > 0) deletedCount++
                        }
                        if (deletedCount > 0) {
                            finishWithSuccess(true, filePaths)
                            return@runOnUiThread
                        }
                    } catch (sec: SecurityException) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && sec is RecoverableSecurityException) {
                            try {
                                activity.startIntentSenderForResult(
                                    sec.userAction.actionIntent.intentSender,
                                    DELETE_INTENT_REQ_CODE,
                                    null, 0, 0, 0, null
                                )
                                return@runOnUiThread
                            } catch (e: Exception) {
                                Log.w(TAG, "Recoverable dialog launch failed: ${e.message}")
                            }
                        }
                    }
                }

                // Direct file system unlinking fallback (Android 9 and below, app-private storage, or unindexed files)
                val allOk = deleteDirectFallback(uris, filePaths)
                finishWithSuccess(allOk, filePaths)

            } catch (e: Exception) {
                Log.e(TAG, "Deletion error: ${e.message}", e)
                dispatchError("DELETE_FAILED", e.message)
            }
        }
    }

    private fun deleteDirectFallback(uris: List<Uri>, filePaths: List<String>): Boolean {
        val count = maxOf(uris.size, filePaths.size)
        if (count == 0) return false
        var allOk = true
        for (i in 0 until count) {
            val uri = uris.getOrNull(i)
            val path = filePaths.getOrNull(i) ?: ""
            if (!directDelete(uri, path)) {
                allOk = false
            }
        }
        return allOk
    }

    // Called from MainActivity.onActivityResult
    @Suppress("UNUSED_PARAMETER")
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != DELETE_INTENT_REQ_CODE) return false

        val result = pendingResult ?: return true
        val filePaths = pendingFilePaths

        if (resultCode == Activity.RESULT_OK) {
            Log.d(TAG, "System delete dialog APPROVED by user")
            for (path in filePaths) {
                if (path.isNotEmpty()) {
                    try { File(path).delete() } catch (_: Exception) {}
                    try { MediaScannerConnection.scanFile(context, arrayOf(path), null, null) } catch (_: Exception) {}
                }
            }
            dispatchSuccess(true)
        } else {
            Log.d(TAG, "System delete dialog DENIED/CANCELLED by user")
            dispatchSuccess(false)
        }

        // Keep reference until dispatchSuccess completes
        @Suppress("UNUSED_EXPRESSION")
        result
        return true
    }

    private fun directDelete(itemUri: Uri?, filePath: String): Boolean {
        var deleted = false
        if (itemUri != null) {
            try {
                val rows = context.contentResolver.delete(itemUri, null, null)
                if (rows > 0) deleted = true
            } catch (_: Exception) {}
        }
        if (filePath.isNotEmpty()) {
            try {
                val f = File(filePath)
                if (f.exists()) {
                    if (f.delete()) deleted = true
                } else {
                    deleted = true
                }
                MediaScannerConnection.scanFile(context, arrayOf(filePath), null, null)
            } catch (_: Exception) {}
        }
        return deleted
    }

    private fun finishWithSuccess(ok: Boolean, filePaths: List<String>) {
        if (ok) {
            for (path in filePaths) {
                if (path.isNotEmpty()) {
                    try { MediaScannerConnection.scanFile(context, arrayOf(path), null, null) } catch (_: Exception) {}
                }
            }
        }
        dispatchSuccess(ok)
    }

    private fun dispatchSuccess(success: Boolean) {
        val res = pendingResult
        resetPendingState()
        mainHandler.post {
            try {
                res?.success(success)
            } catch (_: Exception) {}
        }
    }

    private fun dispatchError(code: String, message: String?) {
        val res = pendingResult
        resetPendingState()
        mainHandler.post {
            try {
                res?.error(code, message, null)
            } catch (_: Exception) {}
        }
    }

    private fun resetPendingState() {
        pendingResult = null
        pendingUris = emptyList()
        pendingFilePaths = emptyList()
    }

    private fun findUriFromPath(filePath: String): Uri? {
        return try {
            val resolver = context.contentResolver
            val contentUri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            val projection = arrayOf(MediaStore.Audio.Media._ID)
            val selection = "${MediaStore.Audio.Media.DATA}=?"
            val selectionArgs = arrayOf(filePath)
            resolver.query(contentUri, projection, selection, selectionArgs, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val id = cursor.getLong(0)
                    ContentUris.withAppendedId(contentUri, id)
                } else null
            }
        } catch (e: Exception) {
            Log.w(TAG, "findUriFromPath failed: ${e.message}")
            null
        }
    }
}