package com.souljalazian.lotus_player

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.OptIn
import androidx.core.app.ServiceCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.CommandButton
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.MediaNotification
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionCommands
import androidx.media3.session.SessionError
import androidx.media3.session.SessionResult
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import java.util.Collections

@OptIn(UnstableApi::class)
class LotusMediaPlaybackService : MediaSessionService() {

    private var player: ExoPlayer? = null
    private var mediaSession: MediaSession? = null
    private var bitmapLoader: LotusBitmapLoader? = null

    private var bluetoothResumeHandler: Handler? = null
    private var bluetoothResumeRunnable: Runnable? = null

    private val becomingNoisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != AudioManager.ACTION_AUDIO_BECOMING_NOISY) return
            val current = player
            if (current != null && current.isPlaying) {
                pausedByHeadsetDisconnect = true
                Log.d(TAG, "Headset disconnected while playing — will auto-resume on reconnect")
            }
        }
    }

    private val bluetoothDeviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
            if (!addedDevices.any { it.isBluetoothOutput() }) return
            maybeResumeAfterBluetoothReconnect()
        }
    }

    override fun onCreate() {
        super.onCreate()
        isShuttingDown = false
        Log.i(TAG, "LotusMediaPlaybackService onCreate()")

        ensureMediaNotificationChannel()

        val baseNotificationProvider = DefaultMediaNotificationProvider.Builder(this)
            .setChannelId(MEDIA_CHANNEL_ID)
            .build()
            .apply {
                setSmallIcon(R.drawable.ic_stat_lotus)
            }

        val dismissAwareProvider = object : MediaNotification.Provider {
            override fun createNotification(
                mediaSession: MediaSession,
                customLayout: ImmutableList<CommandButton>,
                actionFactory: MediaNotification.ActionFactory,
                onNotificationChangedCallback: MediaNotification.Provider.Callback
            ): MediaNotification {
                val mediaNotif = baseNotificationProvider.createNotification(
                    mediaSession,
                    customLayout,
                    actionFactory,
                    onNotificationChangedCallback
                )
                val dismissIntent = Intent(
                    this@LotusMediaPlaybackService,
                    LotusMediaPlaybackService::class.java
                ).apply {
                    action = ACTION_DISMISS_APP
                }
                val dismissPendingIntent = PendingIntent.getService(
                    this@LotusMediaPlaybackService,
                    DISMISS_REQ_CODE,
                    dismissIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                mediaNotif.notification.deleteIntent = dismissPendingIntent
                return mediaNotif
            }

            override fun handleCustomCommand(
                session: MediaSession,
                action: String,
                extras: Bundle
            ): Boolean {
                return baseNotificationProvider.handleCustomCommand(session, action, extras)
            }

            override fun getNotificationChannelInfo(): MediaNotification.Provider.NotificationChannelInfo {
                return baseNotificationProvider.notificationChannelInfo
            }
        }
        setMediaNotificationProvider(dismissAwareProvider)

        val audioAttributes = AudioAttributes.Builder()
            .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
            .setUsage(C.USAGE_MEDIA)
            .build()

        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(10_000, 20_000, 500, 1_000)
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

        val exoPlayer = ExoPlayer.Builder(this)
            .setLoadControl(loadControl)
            .setAudioAttributes(audioAttributes, true)
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_LOCAL)
            .setSeekBackIncrementMs(5000)
            .setSeekForwardIncrementMs(5000)
            .build()

        player = exoPlayer
        activePlayer = exoPlayer

        exoPlayer.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (!isShuttingDown) {
                    LotusAudioFxController.notifyPlaybackActive(isPlaying)
                }
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (isShuttingDown) return
                when (playbackState) {
                    Player.STATE_IDLE -> Log.d(TAG, "Playback state: IDLE")
                    Player.STATE_BUFFERING -> Log.d(TAG, "Playback state: BUFFERING")
                    Player.STATE_READY -> Log.d(TAG, "Playback state: READY")
                    Player.STATE_ENDED -> Log.d(TAG, "Playback state: ENDED")
                }
            }

            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                if (isShuttingDown) return
                val mediaId = mediaItem?.mediaId ?: ""
                if (mediaId.isNotEmpty()) {
                    val isFav = favoriteMediaIds.contains(mediaId)
                    if (favoriteState != isFav) {
                        favoriteState = isFav
                        applyFavoriteButtonToSession(mediaSession, isFav)
                    }
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                Log.e(TAG, "ExoPlayer error [${error.errorCodeName}]: ${error.message}", error)
            }
        })

        val sessionPlayer = LotusSessionPlayer(exoPlayer) {
            Handler(Looper.getMainLooper()).post {
                shutdownServiceAndApp(closeActivity = true)
            }
        }

        val sessionCallback = object : MediaSession.Callback {
            override fun onConnect(
                session: MediaSession,
                controller: MediaSession.ControllerInfo
            ): MediaSession.ConnectionResult {
                if (isShuttingDown) {
                    return MediaSession.ConnectionResult.AcceptedResultBuilder()
                        .setAvailablePlayerCommands(Player.Commands.EMPTY)
                        .setAvailableSessionCommands(SessionCommands.EMPTY)
                        .build()
                }
                if (session.isMediaNotificationController(controller)) {
                    val availableSessionCommands = MediaSession.ConnectionResult.DEFAULT_SESSION_COMMANDS
                        .buildUpon()
                        .add(COMMAND_FAVORITE)
                        .build()

                    return MediaSession.ConnectionResult.AcceptedResultBuilder()
                        .setAvailablePlayerCommands(MediaSession.ConnectionResult.DEFAULT_PLAYER_COMMANDS)
                        .setAvailableSessionCommands(availableSessionCommands)
                        .setCustomLayout(ImmutableList.of(getFavoriteButton(favoriteState)))
                        .build()
                }
                return super.onConnect(session, controller)
            }

            override fun onCustomCommand(
                session: MediaSession,
                controller: MediaSession.ControllerInfo,
                customCommand: SessionCommand,
                args: Bundle
            ): ListenableFuture<SessionResult> {
                if (isShuttingDown) {
                    return Futures.immediateFuture(SessionResult(SessionError.ERROR_UNKNOWN))
                }
                if (customCommand.customAction == CUSTOM_ACTION_FAVORITE) {
                    toggleFavorite()
                    return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
                }
                return super.onCustomCommand(session, controller, customCommand, args)
            }

            override fun onDisconnected(session: MediaSession, controller: MediaSession.ControllerInfo) {
                if (session.isMediaNotificationController(controller) && !isShuttingDown) {
                    Log.d(TAG, "Notification controller disconnected")
                }
                super.onDisconnected(session, controller)
            }
        }

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val sessionActivity = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val loader = LotusBitmapLoader(applicationContext)
        bitmapLoader = loader

        val session = MediaSession.Builder(this, sessionPlayer)
            .setSessionActivity(sessionActivity)
            .setBitmapLoader(loader)
            .setCustomLayout(ImmutableList.of(getFavoriteButton(favoriteState)))
            .setCallback(sessionCallback)
            .build()

        mediaSession = session
        activeSession = session
        addSession(session)

        appContext = applicationContext
        LotusMedia3Bridge.onServiceReady()

        try {
            registerReceiver(
                becomingNoisyReceiver,
                IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to register becoming-noisy receiver: ${e.message}")
        }
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            audioManager?.registerAudioDeviceCallback(
                bluetoothDeviceCallback,
                Handler(Looper.getMainLooper())
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to register Bluetooth device callback: ${e.message}")
        }
    }

    override fun onUpdateNotification(session: MediaSession, startInForegroundRequired: Boolean) {
        if (isShuttingDown) return
        try {
            super.onUpdateNotification(session, startInForegroundRequired)
        } catch (e: Exception) {
            Log.w(TAG, "onUpdateNotification notice: ${e.message}")
        }
    }

    private fun ensureMediaNotificationChannel() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            if (nm.getNotificationChannel(MEDIA_CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    MEDIA_CHANNEL_ID,
                    "Media Playback Controls",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Active audio playback controls"
                    setShowBadge(false)
                    enableLights(false)
                    enableVibration(false)
                    setSound(null, null)
                }
                nm.createNotificationChannel(channel)
                Log.d(TAG, "Notification channel created")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Channel creation notice: ${e.message}")
        }
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return if (isShuttingDown) null else mediaSession
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_DISMISS_APP) {
            Log.i(TAG, "Media3 notification swiped away (deleteIntent) — closing service & app")
            shutdownServiceAndApp(closeActivity = true)
            return START_NOT_STICKY
        }
        super.onStartCommand(intent, flags, startId)
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "onTaskRemoved: app swiped away by user — closing Media3 service & notification")
        shutdownServiceAndApp(closeActivity = false)
    }

    private fun shutdownServiceAndApp(closeActivity: Boolean) {
        if (isShuttingDown) return
        isShuttingDown = true
        pausedByHeadsetDisconnect = false

        activeSession = null
        activePlayer = null
        appContext = null

        LotusAudioFxController.releaseEffects()

        mediaSession?.let {
            try { removeSession(it) } catch (_: Exception) {}
            try { it.release() } catch (_: Exception) {}
        }
        mediaSession = null

        player?.apply {
            try { pause() } catch (_: Exception) {}
            try { stop() } catch (_: Exception) {}
            try { clearMediaItems() } catch (_: Exception) {}
            try { release() } catch (_: Exception) {}
        }
        player = null

        try {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {}

        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            nm?.cancelAll()
        } catch (_: Exception) {}

        if (closeActivity) {
            MainActivity.closeAppFromNotification()
        }

        stopSelf()
    }

    override fun onDestroy() {
        isShuttingDown = true
        Log.i(TAG, "LotusMediaPlaybackService onDestroy()")
        activeSession = null
        activePlayer = null
        appContext = null

        LotusAudioFxController.releaseEffects()

        mediaSession?.run {
            try { removeSession(this) } catch (_: Exception) {}
            try { release() } catch (_: Exception) {}
            mediaSession = null
        }

        player?.run {
            try { stop() } catch (_: Exception) {}
            try { release() } catch (_: Exception) {}
            player = null
        }

        bitmapLoader?.shutdown()
        bitmapLoader = null

        try { unregisterReceiver(becomingNoisyReceiver) } catch (_: Exception) {}
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            am?.unregisterAudioDeviceCallback(bluetoothDeviceCallback)
        } catch (_: Exception) {}
        bluetoothResumeRunnable?.let { bluetoothResumeHandler?.removeCallbacks(it) }
        bluetoothResumeRunnable = null
        bluetoothResumeHandler = null
        pausedByHeadsetDisconnect = false

        super.onDestroy()
    }

    private class LotusSessionPlayer(
        private val exo: ExoPlayer,
        private val onNotificationStop: () -> Unit
    ) : ForwardingPlayer(exo) {

        private var lastBaseCommands: Player.Commands? = null
        private var cachedCommands: Player.Commands? = null

        override fun getAvailableCommands(): Player.Commands {
            val base = super.getAvailableCommands()
            if (base == lastBaseCommands && cachedCommands != null) {
                return cachedCommands!!
            }
            val built = base.buildUpon()
                .add(COMMAND_SEEK_TO_NEXT)
                .add(COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)
                .add(COMMAND_SEEK_TO_PREVIOUS)
                .add(COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
                .build()
            lastBaseCommands = base
            cachedCommands = built
            return built
        }

        override fun isCommandAvailable(command: Int): Boolean {
            return command == COMMAND_SEEK_TO_NEXT ||
                    command == COMMAND_SEEK_TO_NEXT_MEDIA_ITEM ||
                    command == COMMAND_SEEK_TO_PREVIOUS ||
                    command == COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM ||
                    super.isCommandAvailable(command)
        }

        override fun pause() {
            pausedByHeadsetDisconnect = false
            super.pause()
        }

        override fun stop() {
            if (isShuttingDown) return
            Log.i(TAG, "MediaSession stop() triggered (notification dismissed) — closing service & app")
            onNotificationStop()
        }

        override fun seekToNext() {
            if (isShuttingDown) return
            if (exo.hasNextMediaItem()) {
                super.seekToNext()
            } else {
                LotusMedia3Bridge.instance?.notifySkipRequested(forward = true)
                if (exo.mediaItemCount > 1) {
                    exo.seekTo(0, 0L)
                    if (exo.playbackState == STATE_ENDED || exo.playbackState == STATE_IDLE) {
                        exo.prepare()
                    }
                    exo.play()
                }
            }
        }

        override fun seekToNextMediaItem() {
            if (isShuttingDown) return
            if (exo.hasNextMediaItem()) {
                super.seekToNextMediaItem()
            } else {
                LotusMedia3Bridge.instance?.notifySkipRequested(forward = true)
                if (exo.mediaItemCount > 1) {
                    exo.seekTo(0, 0L)
                    if (exo.playbackState == STATE_ENDED || exo.playbackState == STATE_IDLE) {
                        exo.prepare()
                    }
                    exo.play()
                }
            }
        }

        override fun seekToPrevious() {
            if (isShuttingDown) return
            if (exo.currentPosition > 3000L) {
                exo.seekTo(0L)
            } else if (exo.hasPreviousMediaItem()) {
                super.seekToPrevious()
            } else {
                LotusMedia3Bridge.instance?.notifySkipRequested(forward = false)
                if (exo.mediaItemCount > 1) {
                    exo.seekTo(exo.mediaItemCount - 1, 0L)
                    if (exo.playbackState == STATE_ENDED || exo.playbackState == STATE_IDLE) {
                        exo.prepare()
                    }
                    exo.play()
                }
            }
        }

        override fun seekToPreviousMediaItem() {
            if (isShuttingDown) return
            if (exo.hasPreviousMediaItem()) {
                super.seekToPreviousMediaItem()
            } else {
                LotusMedia3Bridge.instance?.notifySkipRequested(forward = false)
                if (exo.mediaItemCount > 1) {
                    exo.seekTo(exo.mediaItemCount - 1, 0L)
                    if (exo.playbackState == STATE_ENDED || exo.playbackState == STATE_IDLE) {
                        exo.prepare()
                    }
                    exo.play()
                }
            }
        }
    }

    private fun AudioDeviceInfo.isBluetoothOutput(): Boolean {
        if (type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
            type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
        ) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                type == AudioDeviceInfo.TYPE_BLE_SPEAKER
            ) return true
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (type == AudioDeviceInfo.TYPE_BLE_BROADCAST) return true
        }
        return false
    }

    private fun maybeResumeAfterBluetoothReconnect() {
        if (isShuttingDown) return
        if (!pausedByHeadsetDisconnect) return
        val exo = player ?: return
        if (exo.playbackState == Player.STATE_IDLE ||
            exo.playbackState == Player.STATE_ENDED ||
            exo.mediaItemCount == 0
        ) {
            pausedByHeadsetDisconnect = false
            return
        }
        if (exo.isPlaying) {
            pausedByHeadsetDisconnect = false
            return
        }

        bluetoothResumeRunnable?.let { bluetoothResumeHandler?.removeCallbacks(it) }

        val handler = bluetoothResumeHandler
            ?: Handler(Looper.getMainLooper()).also { bluetoothResumeHandler = it }

        val runnable = Runnable {
            if (isShuttingDown || !pausedByHeadsetDisconnect) return@Runnable
            val current = player ?: return@Runnable
            val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            val btStillConnected = am?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                ?.any { it.isBluetoothOutput() } == true
            if (!btStillConnected) return@Runnable
            pausedByHeadsetDisconnect = false
            Log.i(TAG, "Bluetooth reconnected — auto-resuming playback")
            current.play()
        }
        bluetoothResumeRunnable = runnable
        handler.postDelayed(runnable, 700L)
    }

    companion object {
        private const val TAG = "LotusMedia3Service"
        const val MEDIA_CHANNEL_ID = "com.souljalazian.lotus_player.media_controls_v2"
        const val ACTION_DISMISS_APP = "com.souljalazian.lotus_player.ACTION_DISMISS_APP"
        private const val DISMISS_REQ_CODE = 9001

        const val CUSTOM_ACTION_FAVORITE = "com.souljalazian.lotus_player.ACTION_FAVORITE"
        val COMMAND_FAVORITE = SessionCommand(CUSTOM_ACTION_FAVORITE, Bundle.EMPTY)

        @Volatile
        var isShuttingDown: Boolean = false
            private set

        @Volatile
        var pausedByHeadsetDisconnect: Boolean = false

        @JvmStatic
        @Suppress("unused")
        fun prepareForShutdown() {
            isShuttingDown = true
        }

        @Volatile
        var activeSession: MediaSession? = null
            private set

        @Volatile
        var activePlayer: ExoPlayer? = null
            private set

        @Volatile
        var favoriteState: Boolean = false

        @Volatile
        var appContext: Context? = null
            private set

        private val favoriteMediaIds: MutableSet<String> =
            Collections.synchronizedSet(HashSet())

        @JvmStatic
        fun getFavoriteButton(isFavorite: Boolean): CommandButton {
            val heartIconRes = if (isFavorite) R.drawable.ic_heart_red else R.drawable.ic_heart_outline
            return CommandButton.Builder(
                if (isFavorite) CommandButton.ICON_HEART_FILLED else CommandButton.ICON_HEART_UNFILLED
            )
                .setCustomIconResId(heartIconRes)
                .setSessionCommand(COMMAND_FAVORITE)
                .setDisplayName(if (isFavorite) "Unfavorite" else "Favorite")
                .build()
        }

        private fun applyFavoriteButtonToSession(session: MediaSession?, isFavorite: Boolean) {
            if (isShuttingDown || session == null) return
            val buttons = ImmutableList.of(getFavoriteButton(isFavorite))
            try {
                val notifController = session.mediaNotificationControllerInfo
                if (notifController != null) {
                    session.setCustomLayout(notifController, buttons)
                } else {
                    session.setCustomLayout(buttons)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to update favorite button: ${e.message}")
            }
        }

        @JvmStatic
        fun setFavoriteMediaIds(ids: Collection<String>) {
            synchronized(favoriteMediaIds) {
                favoriteMediaIds.clear()
                favoriteMediaIds.addAll(ids)
            }
            val currentId = activePlayer?.currentMediaItem?.mediaId ?: ""
            if (currentId.isNotEmpty()) {
                val isFav = favoriteMediaIds.contains(currentId)
                updateFavoriteStatus(isFav, currentId)
            }
        }

        @JvmStatic
        fun setMediaIdFavorite(mediaId: String, isFavorite: Boolean) {
            if (mediaId.isEmpty()) return
            synchronized(favoriteMediaIds) {
                if (isFavorite) {
                    favoriteMediaIds.add(mediaId)
                } else {
                    favoriteMediaIds.remove(mediaId)
                }
            }
        }

        @JvmStatic
        fun toggleFavorite() {
            if (isShuttingDown) return
            val newState = !favoriteState
            favoriteState = newState
            val currentId = activePlayer?.currentMediaItem?.mediaId ?: ""
            if (currentId.isNotEmpty()) {
                setMediaIdFavorite(currentId, newState)
            }
            applyFavoriteButtonToSession(activeSession, newState)
            LotusMedia3Bridge.instance?.triggerFavoriteStateChanged(newState, currentId)
        }

        @JvmStatic
        fun updateFavoriteStatus(isFavorite: Boolean, mediaId: String? = null) {
            if (!mediaId.isNullOrEmpty()) {
                setMediaIdFavorite(mediaId, isFavorite)
            }
            if (favoriteState != isFavorite) {
                favoriteState = isFavorite
                applyFavoriteButtonToSession(activeSession, isFavorite)
            }
        }
    }
}