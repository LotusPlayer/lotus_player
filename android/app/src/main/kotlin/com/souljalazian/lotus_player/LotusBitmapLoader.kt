package com.souljalazian.lotus_player

import android.annotation.SuppressLint
import android.content.ComponentCallbacks2
import android.content.ContentResolver
import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.util.LruCache
import android.util.Size
import androidx.annotation.OptIn
import androidx.core.graphics.scale
import androidx.core.net.toUri
import androidx.media3.common.util.BitmapLoader
import androidx.media3.common.util.UnstableApi
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.ListeningExecutorService
import com.google.common.util.concurrent.MoreExecutors
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Collections
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.zip.CRC32

@OptIn(UnstableApi::class)
@SuppressLint("NewApi")
@Suppress("SpellCheckingInspection")
class LotusBitmapLoader(private val context: Context) : BitmapLoader, ComponentCallbacks2 {

    data class ResolvedArtwork(
        val artworkUri: Uri? = null,
        val artworkData: ByteArray? = null
    )

    companion object {
        private const val MAX_ARTWORK_DIM = 192
        private const val JPEG_QUALITY = 82
        private const val BITMAP_CACHE_BYTES = 4 * 1024 * 1024
        private const val JPEG_CACHE_BYTES = 2 * 1024 * 1024
        private const val MAX_NEGATIVE_CACHE = 2000
        private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"

        private val memoryCache = object : LruCache<String, Bitmap>(BITMAP_CACHE_BYTES) {
            override fun sizeOf(key: String, value: Bitmap): Int {
                return value.allocationByteCount.coerceAtLeast(1)
            }
        }

        private val jpegCache = object : LruCache<String, ByteArray>(JPEG_CACHE_BYTES) {
            override fun sizeOf(key: String, value: ByteArray): Int {
                return value.size.coerceAtLeast(1)
            }
        }

        private val missingArtCache: MutableSet<String> = Collections.synchronizedSet(
            object : LinkedHashMap<String, Boolean>(128, 0.75f, true) {
                override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Boolean>?): Boolean {
                    return size > MAX_NEGATIVE_CACHE
                }
            }.let { Collections.newSetFromMap(it) }
        )

        private val removedCoverTracks: MutableSet<String> =
            Collections.synchronizedSet(HashSet())

        private fun bytesCacheKey(data: ByteArray): String {
            val crc = CRC32()
            crc.update(data)
            return "bytes:${data.size}:${crc.value}"
        }

        fun markCoverRemoved(context: Context, trackId: String, removed: Boolean) {
            if (trackId.isEmpty()) return
            if (removed) {
                removedCoverTracks.add(trackId)
            } else {
                removedCoverTracks.remove(trackId)
            }
            try {
                context.getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean("flutter.tag_override_${trackId}_cover_removed", removed)
                    .apply()
            } catch (_: Exception) {}
        }

        fun isCoverRemoved(context: Context, trackId: String): Boolean {
            if (trackId.isEmpty()) return false
            if (removedCoverTracks.contains(trackId)) return true
            return try {
                val removed = context
                    .getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
                    .getBoolean("flutter.tag_override_${trackId}_cover_removed", false)
                if (removed) removedCoverTracks.add(trackId)
                removed
            } catch (_: Exception) {
                false
            }
        }

        private fun getCustomCoverOverridePath(context: Context, trackId: String): String? {
            if (trackId.isEmpty()) return null
            return try {
                val p = context
                    .getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
                    .getString("flutter.tag_override_${trackId}_cover_path", null)
                if (!p.isNullOrEmpty() && File(p).exists()) p else null
            } catch (_: Exception) {
                null
            }
        }

        fun resolveArtworkForMedia3(
            context: Context,
            trackId: String,
            albumId: String,
            candidateUriStr: String?
        ): ResolvedArtwork {
            val cleanCandidate = candidateUriStr?.trim().orEmpty()

            // Respect explicit cover deletion if no new candidate URI was supplied
            if (cleanCandidate.isEmpty() && isCoverRemoved(context, trackId)) {
                return ResolvedArtwork()
            }

            // Check custom gallery cover override stored by tag editor
            val overridePath = if (cleanCandidate.isEmpty()) {
                getCustomCoverOverridePath(context, trackId)
            } else {
                null
            }
            val effectiveCandidate = overridePath ?: cleanCandidate

            // 1. Remote HTTP/HTTPS URL
            if (effectiveCandidate.startsWith("http://", ignoreCase = true) ||
                effectiveCandidate.startsWith("https://", ignoreCase = true)
            ) {
                if (missingArtCache.contains(effectiveCandidate)) return ResolvedArtwork()
                val remoteUri = try { effectiveCandidate.toUri() } catch (_: Exception) { null }
                return ResolvedArtwork(artworkUri = remoteUri)
            }

            // 2. Local file:// or raw file path
            if (effectiveCandidate.startsWith("file://", ignoreCase = true) ||
                effectiveCandidate.startsWith("/")
            ) {
                val fileUri = if (effectiveCandidate.startsWith("/")) {
                    File(effectiveCandidate).toUri()
                } else {
                    try { effectiveCandidate.toUri() } catch (_: Exception) { null }
                }
                val path = fileUri?.path
                if (!path.isNullOrEmpty()) {
                    val key = "file:$path"
                    if (missingArtCache.contains(key)) return ResolvedArtwork()
                    jpegCache.get(key)?.let { cachedBytes ->
                        return ResolvedArtwork(artworkData = cachedBytes)
                    }
                    val file = File(path)
                    if (file.exists() && file.isFile && file.length() > 0L) {
                        val bmp = decodeSampledFile(path)
                        if (bmp != null) {
                            val bytes = cacheBitmapAndEncodeJpeg(key, bmp)
                            if (bytes != null) {
                                return ResolvedArtwork(artworkData = bytes)
                            }
                        }
                    }
                    missingArtCache.add(key)
                    return ResolvedArtwork()
                }
            }

            // 3. MediaStore / physical audio embedded picture lookup
            if (trackId.isNotEmpty() || albumId.isNotEmpty()) {
                val cacheKey = if (trackId.isNotEmpty()) "track:$trackId" else "album:$albumId"
                if (missingArtCache.contains(cacheKey)) {
                    return ResolvedArtwork()
                }
                jpegCache.get(cacheKey)?.let { cachedBytes ->
                    return ResolvedArtwork(artworkData = cachedBytes)
                }

                val bmp = loadMediaStoreBitmap(context, trackId, albumId)
                if (bmp != null) {
                    val bytes = cacheBitmapAndEncodeJpeg(cacheKey, bmp)
                    if (bytes != null) {
                        return ResolvedArtwork(artworkData = bytes)
                    }
                }
                missingArtCache.add(cacheKey)
                return ResolvedArtwork()
            }

            return ResolvedArtwork()
        }

        @Suppress("unused")
        fun resolveArtworkCacheOnly(
            trackId: String,
            albumId: String,
            candidateUriStr: String?
        ): ResolvedArtwork {
            val cleanCandidate = candidateUriStr?.trim().orEmpty()

            if (cleanCandidate.isEmpty() && removedCoverTracks.contains(trackId)) {
                return ResolvedArtwork()
            }

            if (cleanCandidate.startsWith("file://", ignoreCase = true) ||
                cleanCandidate.startsWith("/")
            ) {
                val path = if (cleanCandidate.startsWith("/")) {
                    cleanCandidate
                } else {
                    try { cleanCandidate.toUri().path } catch (_: Exception) { null }
                }
                if (!path.isNullOrEmpty()) {
                    jpegCache.get("file:$path")?.let { return ResolvedArtwork(artworkData = it) }
                }
                return ResolvedArtwork()
            }

            if (trackId.isNotEmpty() || albumId.isNotEmpty()) {
                val key = if (trackId.isNotEmpty()) "track:$trackId" else "album:$albumId"
                jpegCache.get(key)?.let { return ResolvedArtwork(artworkData = it) }
            }

            return ResolvedArtwork()
        }

        private fun loadMediaStoreBitmap(
            context: Context,
            trackId: String,
            albumId: String
        ): Bitmap? {
            val trackNum = trackId.toLongOrNull() ?: 0L
            val albumNum = albumId.toLongOrNull() ?: 0L

            // 1. Read directly from the audio file via MediaMetadataRetriever first so
            // physical APIC additions or removals take immediate effect without waiting
            // for Android's MediaStore thumbnail cache to expire.
            if (trackNum > 0L) {
                var retriever: MediaMetadataRetriever? = null
                try {
                    retriever = MediaMetadataRetriever()
                    val mediaUri = "content://media/external/audio/media/$trackNum".toUri()
                    retriever.setDataSource(context, mediaUri)
                    val art = retriever.embeddedPicture
                    if (art != null && art.isNotEmpty()) {
                        decodeSampledByteArray(art)?.let { return it }
                    }
                } catch (_: Exception) {
                } finally {
                    try { retriever?.release() } catch (_: Exception) {}
                }
            }

            // If cover was explicitly removed, never fall back to cached MediaStore thumbnails
            if (isCoverRemoved(context, trackId)) {
                return null
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                if (trackNum > 0L) {
                    val mediaUri = "content://media/external/audio/media/$trackNum".toUri()
                    try {
                        return context.contentResolver.loadThumbnail(
                            mediaUri,
                            Size(MAX_ARTWORK_DIM, MAX_ARTWORK_DIM),
                            null
                        )
                    } catch (_: Exception) {}
                }
                if (albumNum > 0L) {
                    val albumUri = "content://media/external/audio/albums/$albumNum".toUri()
                    try {
                        return context.contentResolver.loadThumbnail(
                            albumUri,
                            Size(MAX_ARTWORK_DIM, MAX_ARTWORK_DIM),
                            null
                        )
                    } catch (_: Exception) {}
                }
            } else {
                if (albumNum > 0L) {
                    val albumArtUri = "content://media/external/audio/albumart/$albumNum".toUri()
                    decodeSampledContentUri(context, albumArtUri)?.let { return it }
                }

                if (trackNum > 0L) {
                    val trackArtUri = "content://media/external/audio/media/$trackNum/albumart".toUri()
                    decodeSampledContentUri(context, trackArtUri)?.let { return it }
                }
            }

            return null
        }

        private fun cacheBitmapAndEncodeJpeg(cacheKey: String, rawBitmap: Bitmap): ByteArray? {
            val optimized = optimizeForNotification(rawBitmap)
            val baos = ByteArrayOutputStream(8192)
            val ok = try {
                optimized.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, baos)
            } catch (_: Exception) {
                false
            }
            if (!ok) return null
            val bytes = baos.toByteArray()
            if (bytes.isEmpty()) return null

            jpegCache.put(cacheKey, bytes)
            memoryCache.put(bytesCacheKey(bytes), optimized)
            return bytes
        }

        fun invalidateTrackCache(
            trackId: String,
            albumId: String? = null,
            candidatePath: String? = null
        ) {
            if (trackId.isNotEmpty()) {
                val key = "track:$trackId"
                missingArtCache.remove(key)
                jpegCache.remove(key)
            }
            if (!albumId.isNullOrEmpty()) {
                val aKey = "album:$albumId"
                missingArtCache.remove(aKey)
                jpegCache.remove(aKey)
            }
            if (!candidatePath.isNullOrEmpty()) {
                val clean = candidatePath.trim()
                val fKey = "file:$clean"
                missingArtCache.remove(fKey)
                jpegCache.remove(fKey)
            }
            memoryCache.evictAll()
        }

        fun trimCachesIfNeeded() {
            val maxSize = MAX_NEGATIVE_CACHE / 2
            synchronized(missingArtCache) {
                if (missingArtCache.size > (MAX_NEGATIVE_CACHE * 0.8).toInt()) {
                    val copy = missingArtCache.toList()
                    missingArtCache.clear()
                    missingArtCache.addAll(copy.takeLast(maxSize))
                }
            }
        }

        private fun loadAndScaleFromUri(context: Context, uri: Uri): Bitmap? {
            val scheme = uri.scheme?.lowercase() ?: ""
            if (scheme == "lotus-art") return null

            if (scheme == ContentResolver.SCHEME_CONTENT) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val uriStr = uri.toString()
                    val targetThumbUri = when {
                        uriStr.endsWith("/albumart") -> uriStr.removeSuffix("/albumart").toUri()
                        uriStr.contains("/audio/media/") && !uriStr.contains("albumart") -> uri
                        else -> null
                    }
                    if (targetThumbUri != null) {
                        try {
                            return context.contentResolver.loadThumbnail(
                                targetThumbUri,
                                Size(MAX_ARTWORK_DIM, MAX_ARTWORK_DIM),
                                null
                            )
                        } catch (_: Exception) {}
                    }
                }
                decodeSampledContentUri(context, uri)?.let { return it }
            } else if (scheme == ContentResolver.SCHEME_FILE || scheme.isEmpty()) {
                val path = uri.path
                if (!path.isNullOrEmpty()) {
                    decodeSampledFile(path)?.let { return it }
                }
            }
            return null
        }

        private fun decodeSampledContentUri(context: Context, uri: Uri): Bitmap? {
            return try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                context.contentResolver.openInputStream(uri)?.use { stream ->
                    BitmapFactory.decodeStream(stream, null, bounds)
                }
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

                val opts = BitmapFactory.Options().apply {
                    inSampleSize = calculateInSampleSize(bounds.outWidth, bounds.outHeight, MAX_ARTWORK_DIM)
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                }
                context.contentResolver.openInputStream(uri)?.use { stream ->
                    BitmapFactory.decodeStream(stream, null, opts)
                }
            } catch (_: Exception) {
                null
            }
        }

        private fun decodeSampledFile(path: String): Bitmap? {
            return try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(path, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

                val opts = BitmapFactory.Options().apply {
                    inSampleSize = calculateInSampleSize(bounds.outWidth, bounds.outHeight, MAX_ARTWORK_DIM)
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                }
                BitmapFactory.decodeFile(path, opts)
            } catch (_: Exception) {
                null
            }
        }

        private fun decodeSampledByteArray(data: ByteArray): Bitmap? {
            return try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

                val opts = BitmapFactory.Options().apply {
                    inSampleSize = calculateInSampleSize(bounds.outWidth, bounds.outHeight, MAX_ARTWORK_DIM)
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                }
                BitmapFactory.decodeByteArray(data, 0, data.size, opts)
            } catch (_: Exception) {
                null
            }
        }

        private fun calculateInSampleSize(width: Int, height: Int, maxDim: Int): Int {
            var inSampleSize = 1
            if (height > maxDim || width > maxDim) {
                val halfHeight = height / 2
                val halfWidth = width / 2
                while ((halfHeight / inSampleSize) >= maxDim && (halfWidth / inSampleSize) >= maxDim) {
                    inSampleSize *= 2
                }
            }
            return inSampleSize
        }

        private fun optimizeForNotification(bitmap: Bitmap): Bitmap {
            var current = bitmap

            if (current.config != Bitmap.Config.ARGB_8888) {
                val soft = current.copy(Bitmap.Config.ARGB_8888, false)
                if (soft != null) {
                    current.recycle()
                    current = soft
                }
            }

            val w = current.width
            val h = current.height
            if (w > MAX_ARTWORK_DIM || h > MAX_ARTWORK_DIM) {
                val ratio = w.toFloat() / h.toFloat()
                val targetW: Int
                val targetH: Int
                if (w >= h) {
                    targetW = MAX_ARTWORK_DIM
                    targetH = (MAX_ARTWORK_DIM / ratio).toInt().coerceAtLeast(1)
                } else {
                    targetH = MAX_ARTWORK_DIM
                    targetW = (MAX_ARTWORK_DIM * ratio).toInt().coerceAtLeast(1)
                }
                val scaled = current.scale(targetW, targetH)
                if (scaled != current) {
                    current.recycle()
                    current = scaled
                }
            }

            return current
        }
    }

    init {
        context.registerComponentCallbacks(this)
    }

    private val executor: ListeningExecutorService = MoreExecutors.listeningDecorator(
        Executors.newSingleThreadExecutor { r ->
            Thread(r, "LotusArtLoader").apply {
                isDaemon = true
                priority = Thread.NORM_PRIORITY - 1
            }
        }
    )

    override fun supportsMimeType(mimeType: String): Boolean {
        return mimeType.startsWith("image/", ignoreCase = true)
    }

    override fun decodeBitmap(data: ByteArray): ListenableFuture<Bitmap> {
        if (data.isEmpty()) {
            return Futures.immediateFailedFuture(IllegalArgumentException("Empty image data"))
        }
        val key = bytesCacheKey(data)
        memoryCache.get(key)?.let { cached ->
            if (!cached.isRecycled) return Futures.immediateFuture(cached)
        }

        return executor.submit(Callable {
            memoryCache.get(key)?.let { cached ->
                if (!cached.isRecycled) return@Callable cached
            }
            val bmp = decodeSampledByteArray(data)
                ?: throw IllegalStateException("Failed to decode artwork bytes")
            val optimized = optimizeForNotification(bmp)
            memoryCache.put(key, optimized)
            optimized
        })
    }

    override fun loadBitmap(uri: Uri): ListenableFuture<Bitmap> {
        val key = uri.toString()
        if (uri.scheme.equals("lotus-art", ignoreCase = true)) {
            return Futures.immediateFailedFuture(IllegalArgumentException("Unsupported scheme: $key"))
        }
        memoryCache.get(key)?.let { cached ->
            if (!cached.isRecycled) {
                return Futures.immediateFuture(cached)
            }
        }
        if (missingArtCache.contains(key)) {
            return Futures.immediateFailedFuture(IllegalStateException("No artwork for $key"))
        }

        return executor.submit(Callable {
            memoryCache.get(key)?.let { cached ->
                if (!cached.isRecycled) return@Callable cached
            }

            val bmp = loadAndScaleFromUri(context, uri)
            if (bmp != null) {
                val optimized = optimizeForNotification(bmp)
                memoryCache.put(key, optimized)
                optimized
            } else {
                missingArtCache.add(key)
                throw IllegalStateException("No artwork for $key")
            }
        })
    }

    override fun onTrimMemory(level: Int) {
        when {
            level >= ComponentCallbacks2.TRIM_MEMORY_COMPLETE -> {
                memoryCache.evictAll()
                jpegCache.evictAll()
            }
            level >= ComponentCallbacks2.TRIM_MEMORY_BACKGROUND -> {
                memoryCache.evictAll()
            }
            level >= ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN -> {
                jpegCache.evictAll()
                trimCachesIfNeeded()
            }
        }
    }

    override fun onLowMemory() {
        memoryCache.evictAll()
        jpegCache.evictAll()
    }

    override fun onConfigurationChanged(newConfig: Configuration) = Unit

    fun shutdown() {
        try { context.unregisterComponentCallbacks(this) } catch (_: Exception) {}
        try { memoryCache.evictAll() } catch (_: Exception) {}
        try { jpegCache.evictAll() } catch (_: Exception) {}
        try { missingArtCache.clear() } catch (_: Exception) {}
        try { executor.shutdownNow() } catch (_: Exception) {}
    }
}