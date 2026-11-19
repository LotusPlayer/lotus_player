@file:Suppress("RedundantQualifierName")

package com.souljalazian.lotus_player

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.core.net.toUri
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

private typealias SongMap = Map<String, Any?>

@OptIn(UnstableApi::class)
class LotusMedia3Bridge(
    messenger: BinaryMessenger,
    context: Context
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val appContext: Context = context.applicationContext

    companion object {
        private const val METHOD_CHANNEL_NAME = "com.souljalazian.lotus_player/media3_controls"
        private const val EVENT_CHANNEL_NAME = "com.souljalazian.lotus_player/media3_events"
        private const val POSITION_THROTTLE_MS = 200L

        @Volatile
        var instance: LotusMedia3Bridge? = null
            private set

        @JvmStatic
        @Suppress("unused")
        fun triggerFavoriteFromNotification() {
            val currentId = LotusMediaPlaybackService.activePlayer?.currentMediaItem?.mediaId ?: ""
            instance?.triggerFavoriteStateChanged(LotusMediaPlaybackService.favoriteState, currentId)
        }

        @JvmStatic
        fun onServiceReady() {
            instance?.attachPlayerListener(LotusMediaPlaybackService.activePlayer)
        }
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL_NAME)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL_NAME)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mediaItemExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "LotusMediaItemBuilder").apply {
            isDaemon = true
            priority = Thread.NORM_PRIORITY
        }
    }
    private val playlistGeneration = AtomicInteger(0)
    private var lastSentEventMap: Map<String, Any?>? = null
    private var lastPositionSentTime = 0L
    private var eventSink: EventChannel.EventSink? = null
    private var playerListener: Player.Listener? = null
    private var lastObservedPlayer: Player? = null

    init {
        instance = this
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    private inline fun runOnMain(crossinline block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post { block() }
        }
    }

    private fun withPlayer(result: Result, block: (Player) -> Unit) {
        val currentPlayer = LotusMediaPlaybackService.activePlayer
        if (currentPlayer != null && Looper.myLooper() == Looper.getMainLooper()) {
            try {
                block(currentPlayer)
            } catch (e: Exception) {
                result.error("PLAYER_ERROR", e.message, null)
            }
            return
        }
        mainHandler.post(object : Runnable {
            var attempts = 0
            override fun run() {
                val p = LotusMediaPlaybackService.activePlayer
                if (p != null) {
                    try {
                        block(p)
                    } catch (e: Exception) {
                        result.error("PLAYER_ERROR", e.message, null)
                    }
                    return
                }
                if (attempts == 0) {
                    try {
                        appContext.startService(Intent(appContext, LotusMediaPlaybackService::class.java))
                    } catch (_: Exception) {}
                }
                attempts++
                if (attempts >= 20) {
                    result.error("SERVICE_NOT_READY", "Media3 service player not available", null)
                    return
                }
                mainHandler.postDelayed(this, 100)
            }
        })
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "play" -> withPlayer(result) { p ->
                if (p.playbackState == Player.STATE_IDLE || p.playbackState == Player.STATE_ENDED) {
                    if (p.playbackState == Player.STATE_ENDED) p.seekToDefaultPosition()
                    p.prepare()
                }
                p.play()
                result.success(true)
            }
            "pause" -> withPlayer(result) {
                LotusMediaPlaybackService.pausedByHeadsetDisconnect = false
                it.pause()
                result.success(true)
            }
            "stop" -> withPlayer(result) { it.stop(); result.success(true) }
            "seek" -> {
                val positionMs = (call.argument<Any>("positionMs") as? Number)?.toLong() ?: 0L
                withPlayer(result) { it.seekTo(positionMs); result.success(true) }
            }
            "skipToNext" -> withPlayer(result) { p ->
                if (p.hasNextMediaItem()) {
                    p.seekToNextMediaItem()
                    result.success(true)
                } else if (p.mediaItemCount > 1) {
                    p.seekTo(0, 0L)
                    if (p.playbackState == Player.STATE_IDLE || p.playbackState == Player.STATE_ENDED) {
                        p.prepare()
                    }
                    p.play()
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            "skipToPrevious" -> withPlayer(result) { p ->
                if (p.hasPreviousMediaItem()) {
                    p.seekToPreviousMediaItem()
                    result.success(true)
                } else if (p.mediaItemCount > 1) {
                    p.seekTo(p.mediaItemCount - 1, 0L)
                    if (p.playbackState == Player.STATE_IDLE || p.playbackState == Player.STATE_ENDED) {
                        p.prepare()
                    }
                    p.play()
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            "setShuffle" -> {
                val enabled = (call.argument<Any>("enabled") as? Boolean) ?: false
                withPlayer(result) { p ->
                    p.shuffleModeEnabled = enabled
                    result.success(true)
                }
            }
            "setRepeatMode" -> {
                val mode = (call.argument<Any>("mode") as? Number)?.toInt() ?: Player.REPEAT_MODE_OFF
                withPlayer(result) { p ->
                    p.repeatMode = mode
                    result.success(true)
                }
            }
            "setSpeedAndPitch" -> {
                val speed = (call.argument<Any>("speed") as? Number)?.toFloat() ?: 1.0f
                val pitch = (call.argument<Any>("pitch") as? Number)?.toFloat() ?: 1.0f
                withPlayer(result) { p ->
                    p.playbackParameters = PlaybackParameters(speed, pitch)
                    result.success(true)
                }
            }
            "setVolume" -> {
                val volume = (call.argument<Any>("volume") as? Number)?.toFloat()?.coerceIn(0f, 1f) ?: 1f
                withPlayer(result) { p -> p.volume = volume; result.success(true) }
            }
            "updateSongMetadata" -> {
                val id = extractIdString(call.argument<Any>("id"))
                val albumId = extractIdString(call.argument<Any>("albumId"))
                val title = call.argument<String>("title") ?: "Unknown Title"
                val artist = call.argument<String>("artist") ?: "Unknown Artist"
                val album = call.argument<String>("album") ?: ""
                val coverPath = (call.argument<String>("coverPath") ?: "").trim()
                val removeCover = call.argument<Boolean>("removeCover") ?: false

                if (id.isEmpty()) {
                    result.success(false)
                    return
                }

                LotusBitmapLoader.markCoverRemoved(appContext, id, removeCover)
                LotusBitmapLoader.invalidateTrackCache(
                    trackId = id,
                    albumId = albumId.ifEmpty { null },
                    candidatePath = coverPath.ifEmpty { null }
                )

                mediaItemExecutor.execute {
                    val metadataExtras = android.os.Bundle(2).apply {
                        putString("lotus_album_id", albumId)
                        putString("lotus_art_uri", if (removeCover) "" else coverPath)
                    }
                    val metadataBuilder = MediaMetadata.Builder()
                        .setTitle(title)
                        .setArtist(artist)
                        .setAlbumTitle(album)
                        .setExtras(metadataExtras)

                    if (!removeCover) {
                        val resolvedArt = LotusBitmapLoader.resolveArtworkForMedia3(
                            context = appContext,
                            trackId = id,
                            albumId = albumId,
                            candidateUriStr = coverPath.ifEmpty { null }
                        )
                        if (resolvedArt.artworkData != null) {
                            metadataBuilder.setArtworkData(
                                resolvedArt.artworkData,
                                MediaMetadata.PICTURE_TYPE_FRONT_COVER
                            )
                        } else if (resolvedArt.artworkUri != null) {
                            metadataBuilder.setArtworkUri(resolvedArt.artworkUri)
                        }
                    }

                    val newMetadata = metadataBuilder.build()

                    mainHandler.post {
                        val p = LotusMediaPlaybackService.activePlayer
                        if (p == null) {
                            result.success(false)
                            return@post
                        }
                        var updatedCount = 0
                        for (i in 0 until p.mediaItemCount) {
                            val existingItem = p.getMediaItemAt(i)
                            if (existingItem.mediaId == id) {
                                // Keep exact localConfiguration/uri so ExoPlayer updates
                                // metadata & notification seamlessly without restarting audio.
                                val updatedItem = existingItem.buildUpon()
                                    .setMediaMetadata(newMetadata)
                                    .build()
                                p.replaceMediaItem(i, updatedItem)
                                updatedCount++
                            }
                        }
                        result.success(updatedCount > 0)
                    }
                }
            }
            "setPlaylist" -> {
                val rawList = call.argument<Any>("songs") as? Iterable<*>
                val startIndex = (call.argument<Any>("startIndex") as? Number)?.toInt() ?: 0
                val startPosMs = (call.argument<Any>("startPosMs") as? Number)?.toLong() ?: 0L
                if (rawList == null) {
                    result.error("INVALID_ARGUMENT", "songs cannot be null", null)
                    return
                }
                val songMaps = extractMapList(rawList)
                syncFavoritesFromPlaylistMaps(songMaps, startIndex)
                val incomingIds = songMaps.map { extractIdString(it["id"]) }
                val gen = playlistGeneration.incrementAndGet()
                val lastIndex = incomingIds.size - 1
                val safeStartIndex = if (lastIndex >= 0) startIndex.coerceIn(0, lastIndex) else 0
                mainHandler.post {
                    val existing = LotusMediaPlaybackService.activePlayer
                    if (existing != null && !existing.shuffleModeEnabled && incomingIds.isNotEmpty()) {
                        val currentIds = currentTimelineMediaIds(existing)
                        if (currentIds != null && currentIds == incomingIds) {
                            withPlayer(result) { p ->
                                if (p.currentMediaItemIndex != safeStartIndex ||
                                    (startPosMs > 0L && kotlin.math.abs(p.currentPosition - startPosMs) > 500L)
                                ) {
                                    p.seekTo(safeStartIndex, startPosMs)
                                }
                                if (p.playbackState == Player.STATE_IDLE || p.playbackState == Player.STATE_ENDED) {
                                    p.prepare()
                                }
                                p.play()
                                result.success(true)
                            }
                            return@post
                        }
                    }
                    mediaItemExecutor.execute {
                        val mediaItems = ArrayList<MediaItem>(songMaps.size)
                        for ((index, songMap) in songMaps.withIndex()) {
                            if (playlistGeneration.get() != gen) break
                            val isCurrent = (index == safeStartIndex)
                            mediaItems.add(buildMediaItem(songMap, isCurrentTrack = isCurrent))
                        }
                        mainHandler.post {
                            if (playlistGeneration.get() != gen) {
                                result.success(false)
                                return@post
                            }
                            withPlayer(result) { p ->
                                p.setMediaItems(mediaItems, safeStartIndex, startPosMs)
                                p.prepare()
                                p.play()
                                result.success(true)
                            }
                        }
                    }
                }
            }
            "appendPlaylistItems" -> {
                val rawList = call.argument<Any>("songs") as? Iterable<*>
                if (rawList == null) {
                    result.success(false)
                    return
                }
                val songMaps = extractMapList(rawList)
                syncFavoritesFromPlaylistMaps(songMaps, -1)
                val gen = playlistGeneration.get()
                mediaItemExecutor.execute {
                    val mediaItems = ArrayList<MediaItem>(songMaps.size)
                    for (songMap in songMaps) {
                        if (playlistGeneration.get() != gen) break
                        mediaItems.add(buildMediaItem(songMap, isCurrentTrack = false))
                    }
                    mainHandler.post {
                        if (playlistGeneration.get() != gen) {
                            result.success(false)
                            return@post
                        }
                        withPlayer(result) { p ->
                            if (p.mediaItemCount == 0) {
                                result.success(false)
                                return@withPlayer
                            }
                            p.addMediaItems(mediaItems)
                            result.success(true)
                        }
                    }
                }
            }
            "prependPlaylistItems" -> {
                val rawList = call.argument<Any>("songs") as? Iterable<*>
                val insertAt = (call.argument<Any>("insertAt") as? Number)?.toInt() ?: 0
                if (rawList == null) {
                    result.success(false)
                    return
                }
                val songMaps = extractMapList(rawList)
                syncFavoritesFromPlaylistMaps(songMaps, -1)
                val gen = playlistGeneration.get()
                mediaItemExecutor.execute {
                    val mediaItems = ArrayList<MediaItem>(songMaps.size)
                    for (songMap in songMaps) {
                        if (playlistGeneration.get() != gen) break
                        mediaItems.add(buildMediaItem(songMap, isCurrentTrack = false))
                    }
                    mainHandler.post {
                        if (playlistGeneration.get() != gen) {
                            result.success(false)
                            return@post
                        }
                        withPlayer(result) { p ->
                            if (p.mediaItemCount == 0) {
                                result.success(false)
                                return@withPlayer
                            }
                            val safeIndex = insertAt.coerceIn(0, p.mediaItemCount)
                            p.addMediaItems(safeIndex, mediaItems)
                            result.success(true)
                        }
                    }
                }
            }
            "syncFavoriteIds" -> {
                val idsRaw = call.argument<Any>("favoriteIds") as? Iterable<*>
                val ids = ArrayList<String>()
                if (idsRaw != null) {
                    for (raw in idsRaw) {
                        when (raw) {
                            is Number -> ids.add(raw.toLong().toString())
                            is String -> ids.add(raw)
                        }
                    }
                }
                runOnMain {
                    LotusMediaPlaybackService.setFavoriteMediaIds(ids)
                    result.success(true)
                }
            }
            "updateFavoriteStatus" -> {
                val isFavorite = (call.argument<Any>("isFavorite") as? Boolean) ?: false
                val songId = when (val songIdRaw = call.argument<Any>("songId")) {
                    is Number -> songIdRaw.toLong().toString()
                    is String -> songIdRaw
                    else -> null
                }
                runOnMain {
                    LotusMediaPlaybackService.updateFavoriteStatus(isFavorite, songId)
                    result.success(true)
                }
            }
            "getPlaybackSnapshot", "getPlaybackState" -> {
                val p = LotusMediaPlaybackService.activePlayer
                val stateMap = HashMap<String, Any?>()
                if (p != null) {
                    val isReallyPlaying = p.isPlaying || (p.playWhenReady && p.playbackState == Player.STATE_BUFFERING)
                    stateMap["isPlaying"] = isReallyPlaying
                    stateMap["playWhenReady"] = p.playWhenReady
                    stateMap["currentPositionMs"] = p.currentPosition.coerceAtLeast(0L)
                    stateMap["durationMs"] = p.duration.coerceAtLeast(0L)
                    stateMap["playbackState"] = p.playbackState
                    stateMap["shuffleEnabled"] = p.shuffleModeEnabled
                    stateMap["repeatMode"] = p.repeatMode
                    stateMap["isFavorite"] = LotusMediaPlaybackService.favoriteState
                    stateMap["audioSessionId"] = p.audioSessionId
                    stateMap["currentMediaId"] = p.currentMediaItem?.mediaId ?: ""
                }
                result.success(stateMap)
            }
            "seekTo" -> {
                val positionMs = (call.argument<Any>("position") as? Number)?.toLong() ?: 0L
                withPlayer(result) { it.seekTo(positionMs); result.success(true) }
            }
            "seekToNext" -> withPlayer(result) { p ->
                val hadNext = p.hasNextMediaItem()
                if (hadNext) p.seekToNextMediaItem()
                result.success(hadNext)
            }
            "seekToPrevious" -> withPlayer(result) { p ->
                val hadPrev = p.hasPreviousMediaItem()
                if (hadPrev) p.seekToPreviousMediaItem()
                result.success(hadPrev)
            }
            "setShuffleModeEnabled" -> {
                val enabled = (call.argument<Any>("enabled") as? Boolean) ?: false
                withPlayer(result) { p ->
                    p.shuffleModeEnabled = enabled
                    result.success(true)
                }
            }
            "setPlaybackSpeed" -> {
                val speed = (call.argument<Any>("speed") as? Number)?.toFloat() ?: 1.0f
                withPlayer(result) { p ->
                    p.playbackParameters = PlaybackParameters(speed)
                    result.success(true)
                }
            }
            "setMediaItems" -> {
                val rawList = call.argument<Any>("items") as? Iterable<*>
                val startIndex = (call.argument<Any>("startIndex") as? Number)?.toInt() ?: 0
                val startPositionMs = (call.argument<Any>("startPositionMs") as? Number)?.toLong() ?: 0L
                val autoPlay = (call.argument<Any>("autoPlay") as? Boolean) ?: true
                if (rawList == null) {
                    result.error("INVALID_ARGUMENT", "Media items list cannot be null", null)
                    return
                }
                val itemMaps = extractMapList(rawList)
                syncFavoritesFromPlaylistMaps(itemMaps, startIndex)
                val incomingIds = itemMaps.map { extractIdString(it["id"]) }
                val gen = playlistGeneration.incrementAndGet()
                val lastIndex = incomingIds.size - 1
                val safeStartIndex = if (lastIndex >= 0) startIndex.coerceIn(0, lastIndex) else 0
                mainHandler.post {
                    val existing = LotusMediaPlaybackService.activePlayer
                    if (existing != null && !existing.shuffleModeEnabled && incomingIds.isNotEmpty()) {
                        val currentIds = currentTimelineMediaIds(existing)
                        if (currentIds != null && currentIds == incomingIds) {
                            withPlayer(result) { p ->
                                if (p.currentMediaItemIndex != safeStartIndex ||
                                    (startPositionMs > 0L && kotlin.math.abs(p.currentPosition - startPositionMs) > 500L)
                                ) {
                                    p.seekTo(safeStartIndex, startPositionMs)
                                }
                                if (p.playbackState == Player.STATE_IDLE || p.playbackState == Player.STATE_ENDED) {
                                    p.prepare()
                                }
                                if (autoPlay) p.play()
                                result.success(true)
                            }
                            return@post
                        }
                    }
                    mediaItemExecutor.execute {
                        val mediaItems = ArrayList<MediaItem>(itemMaps.size)
                        for ((index, itemMap) in itemMaps.withIndex()) {
                            if (playlistGeneration.get() != gen) break
                            val isCurrent = (index == safeStartIndex)
                            mediaItems.add(buildMediaItem(itemMap, isCurrentTrack = isCurrent))
                        }
                        mainHandler.post {
                            if (playlistGeneration.get() != gen) {
                                result.success(false)
                                return@post
                            }
                            withPlayer(result) { p ->
                                p.setMediaItems(mediaItems, safeStartIndex, startPositionMs)
                                p.prepare()
                                if (autoPlay) p.play()
                                result.success(true)
                            }
                        }
                    }
                }
            }
            "setFavorite" -> {
                val isFavorite = (call.argument<Any>("isFavorite") as? Boolean) ?: false
                runOnMain {
                    LotusMediaPlaybackService.updateFavoriteStatus(isFavorite)
                    result.success(true)
                }
            }
            "getFavoriteState" -> result.success(LotusMediaPlaybackService.favoriteState)
            else -> result.notImplemented()
        }
    }

    private fun extractMapList(rawList: Iterable<*>): List<SongMap> {
        val result = ArrayList<SongMap>()
        for (entry in rawList) {
            if (entry is Map<*, *>) {
                val typedMap = HashMap<String, Any?>()
                for ((k, v) in entry) {
                    if (k is String) {
                        typedMap[k] = v
                    }
                }
                result.add(typedMap)
            }
        }
        return result
    }

    private fun syncFavoritesFromPlaylistMaps(songs: List<SongMap>, startIndex: Int) {
        if (songs.isEmpty()) return
        for (map in songs) {
            val isFav = map["isFavorite"] as? Boolean ?: continue
            val id = extractIdString(map["id"])
            if (id.isNotEmpty()) {
                LotusMediaPlaybackService.setMediaIdFavorite(id, isFav)
            }
        }
        if (startIndex >= 0) {
            val startMap = songs.getOrNull(startIndex) ?: return
            val startFav = startMap["isFavorite"] as? Boolean ?: return
            LotusMediaPlaybackService.updateFavoriteStatus(startFav, extractIdString(startMap["id"]))
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        detachPlayerListener()
        attachPlayerListener(LotusMediaPlaybackService.activePlayer)
        val p = LotusMediaPlaybackService.activePlayer
        if (p != null) {
            lastSentEventMap = null
            sendEvent(buildSnapshotMap(p, "onListen"))
        }
    }

    override fun onCancel(arguments: Any?) {
        detachPlayerListener()
        eventSink = null
        lastSentEventMap = null
    }

    fun attachPlayerListener(player: Player?) {
        if (player == null || player == lastObservedPlayer) return
        detachPlayerListener()
        lastObservedPlayer = player
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                val p = LotusMediaPlaybackService.activePlayer ?: return
                sendEvent(buildSnapshotMap(p, "onIsPlayingChanged"))
            }
            override fun onPlaybackStateChanged(playbackState: Int) {
                val p = LotusMediaPlaybackService.activePlayer ?: return
                sendEvent(buildSnapshotMap(p, "onPlaybackStateChanged"))
            }
            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                val p = LotusMediaPlaybackService.activePlayer ?: return
                val map = buildSnapshotMap(p, "onMediaItemTransition").toMutableMap()
                map["index"] = p.currentMediaItemIndex
                map["title"] = mediaItem?.mediaMetadata?.title?.toString() ?: ""
                map["artist"] = mediaItem?.mediaMetadata?.artist?.toString() ?: ""
                sendEvent(map)
            }
            override fun onPositionDiscontinuity(
                oldPosition: Player.PositionInfo,
                newPosition: Player.PositionInfo,
                reason: Int
            ) {
                val p = LotusMediaPlaybackService.activePlayer ?: return
                val now = System.currentTimeMillis()
                if (reason == Player.DISCONTINUITY_REASON_AUTO_TRANSITION ||
                    now - lastPositionSentTime < POSITION_THROTTLE_MS) {
                    return
                }
                lastPositionSentTime = now
                val map = buildSnapshotMap(p, "onPositionDiscontinuity").toMutableMap()
                map["currentPositionMs"] = newPosition.positionMs.coerceAtLeast(0L)
                sendEvent(map)
            }
            override fun onShuffleModeEnabledChanged(shuffleModeEnabled: Boolean) {
                val p = LotusMediaPlaybackService.activePlayer ?: return
                sendEvent(buildSnapshotMap(p, "onShuffleModeEnabledChanged"))
            }
            override fun onRepeatModeChanged(repeatMode: Int) {
                val p = LotusMediaPlaybackService.activePlayer ?: return
                sendEvent(buildSnapshotMap(p, "onRepeatModeChanged"))
            }
            override fun onPlayerError(error: PlaybackException) {
                sendEvent(
                    mapOf(
                        "event" to "onPlayerError",
                        "errorCode" to error.errorCode,
                        "errorMessage" to (error.message ?: "")
                    )
                )
            }
        }
        player.addListener(listener)
        playerListener = listener
    }

    private fun buildSnapshotMap(p: Player, eventName: String): SongMap {
        val isReallyPlaying = p.isPlaying || (p.playWhenReady && p.playbackState == Player.STATE_BUFFERING)
        return mapOf(
            "event" to eventName,
            "isPlaying" to isReallyPlaying,
            "playWhenReady" to p.playWhenReady,
            "currentPositionMs" to p.currentPosition.coerceAtLeast(0L),
            "durationMs" to p.duration.coerceAtLeast(0L),
            "playbackState" to p.playbackState,
            "repeatMode" to p.repeatMode,
            "shuffleEnabled" to p.shuffleModeEnabled,
            "currentMediaId" to (p.currentMediaItem?.mediaId ?: ""),
            "audioSessionId" to p.audioSessionId,
            "isFavorite" to LotusMediaPlaybackService.favoriteState
        )
    }

    fun detachPlayerListener() {
        val player = lastObservedPlayer ?: LotusMediaPlaybackService.activePlayer
        playerListener?.let { listener ->
            player?.removeListener(listener)
        }
        playerListener = null
        lastObservedPlayer = null
    }

    fun triggerFavoriteStateChanged(isFavorite: Boolean, mediaId: String = "") {
        val resolvedId = mediaId.ifEmpty {
            LotusMediaPlaybackService.activePlayer?.currentMediaItem?.mediaId ?: ""
        }
        sendEvent(
            mapOf(
                "event" to "onFavoriteChanged",
                "isFavorite" to isFavorite,
                "mediaId" to resolvedId,
                "currentMediaId" to resolvedId
            )
        )
    }

    fun notifySkipRequested(forward: Boolean) {
        sendEvent(
            mapOf(
                "event" to "onSkipRequested",
                "forward" to forward
            )
        )
    }

    private fun sendEvent(data: SongMap) {
        runOnMain {
            if (lastSentEventMap == data) return@runOnMain
            lastSentEventMap = data
            eventSink?.success(data)
        }
    }

    private fun extractIdString(idRaw: Any?): String {
        return when (idRaw) {
            is Number -> idRaw.toLong().toString()
            is String -> idRaw
            else -> ""
        }
    }

    private fun currentTimelineMediaIds(p: Player): List<String>? {
        val count = p.mediaItemCount
        if (count <= 0) return null
        val ids = ArrayList<String>(count)
        for (i in 0 until count) {
            ids.add(p.getMediaItemAt(i).mediaId)
        }
        return ids
    }

    private fun buildMediaItem(map: SongMap, isCurrentTrack: Boolean = false): MediaItem {
        val id = extractIdString(map["id"])
        val albumId = extractIdString(map["albumId"])
        val uriStr = map["uri"] as? String ?: ""
        val title = map["title"] as? String ?: "Unknown Title"
        val artist = map["artist"] as? String ?: "Unknown Artist"
        val album = map["album"] as? String ?: ""
        val artworkUriStr = (map["artUri"] as? String) ?: (map["artworkUri"] as? String)
        val mediaUri: Uri = if (uriStr.startsWith("content://") ||
            uriStr.startsWith("http://") ||
            uriStr.startsWith("https://")
        ) {
            uriStr.toUri()
        } else {
            val f = File(uriStr)
            if (uriStr.isNotEmpty() && f.canRead()) {
                f.toUri()
            } else if (id.isNotEmpty()) {
                "content://media/external/audio/media/$id".toUri()
            } else {
                f.toUri()
            }
        }
        val metadataExtras = android.os.Bundle(2).apply {
            putString("lotus_album_id", albumId)
            putString("lotus_art_uri", artworkUriStr ?: "")
        }
        val metadataBuilder = MediaMetadata.Builder()
            .setTitle(title)
            .setArtist(artist)
            .setAlbumTitle(album)
            .setExtras(metadataExtras)
        if (isCurrentTrack && !LotusBitmapLoader.isCoverRemoved(appContext, id)) {
            val resolvedArt = LotusBitmapLoader.resolveArtworkForMedia3(
                context = appContext,
                trackId = id,
                albumId = albumId,
                candidateUriStr = artworkUriStr
            )
            if (resolvedArt.artworkData != null) {
                metadataBuilder.setArtworkData(
                    resolvedArt.artworkData,
                    MediaMetadata.PICTURE_TYPE_FRONT_COVER
                )
            } else if (resolvedArt.artworkUri != null) {
                metadataBuilder.setArtworkUri(resolvedArt.artworkUri)
            }
        }
        return MediaItem.Builder()
            .setMediaId(id)
            .setUri(mediaUri)
            .setMediaMetadata(metadataBuilder.build())
            .build()
    }

    fun dispose() {
        playlistGeneration.incrementAndGet()
        detachPlayerListener()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        lastSentEventMap = null
        try { mediaItemExecutor.shutdownNow() } catch (_: Exception) {}
        instance = null
    }
}