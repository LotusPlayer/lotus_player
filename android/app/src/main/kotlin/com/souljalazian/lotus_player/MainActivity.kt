package com.souljalazian.lotus_player

import android.Manifest
import android.annotation.SuppressLint
import android.content.ComponentCallbacks2
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.util.Log
import android.view.Window
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.core.view.WindowCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.ref.WeakReference
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

@SuppressLint("NewApi")
class MainActivity : FlutterActivity(), ComponentCallbacks2 {

    companion object {
        private const val TAG = "LotusMainActivity"
        private const val PERMISSION_REQUEST_CODE = 2026

        private const val INTENT_CHANNEL = "com.souljalazian.lotus_player/intents"
        private const val PERMISSION_CHANNEL = "com.souljalazian.lotus_player/permissions"
        private const val KEY_INITIAL_INTENT = "lotus_initial_intent_data"

        @Volatile
        private var activeInstance: WeakReference<MainActivity>? = null

        @JvmStatic
        fun closeAppFromNotification() {
            val activity = activeInstance?.get() ?: return
            activity.runOnUiThread {
                try {
                    if (!activity.isFinishing && !activity.isDestroyed) {
                        activity.finishAndRemoveTask()
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "closeAppFromNotification notice: ${e.message}")
                }
            }
        }
    }

    private var intentChannel: MethodChannel? = null
    private var permissionChannel: MethodChannel? = null
    private var updaterChannel: MethodChannel? = null
    private var dspFallbackChannel: MethodChannel? = null
    private var playbackFallbackChannel: MethodChannel? = null

    private var media3Bridge: LotusMedia3Bridge? = null
    private var audioFxController: LotusAudioFxController? = null
    private var tagEditorController: LotusTagEditorController? = null
    private var fileDeleterController: LotusFileDeleterController? = null

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var initialIntentData: String? = null
    private val isRequestingPermissions = AtomicBoolean(false)

    private val backgroundExecutor: ExecutorService by lazy {
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "LotusWorker").apply {
                isDaemon = true
                priority = Thread.MIN_PRIORITY
            }
        }
    }

    @Volatile
    private var isEngineConnected: Boolean = false

    @Suppress("DEPRECATION")
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        activeInstance = WeakReference(this)

        try {
            requestWindowFeature(Window.FEATURE_NO_TITLE)
            WindowCompat.setDecorFitsSystemWindows(window, false)

            window.decorView.setBackgroundColor(0xFF050811.toInt())
            window.statusBarColor = Color.TRANSPARENT
            window.navigationBarColor = Color.TRANSPARENT

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                window.isNavigationBarContrastEnforced = false
            }
        } catch (e: Exception) {
            Log.w(TAG, "Window decor setup notice: ${e.message}")
        }

        try {
            val serviceIntent = Intent(this, LotusMediaPlaybackService::class.java)
            startService(serviceIntent)
        } catch (e: Exception) {
            Log.w(TAG, "Media service start notice: ${e.message}")
        }

        if (savedInstanceState != null && initialIntentData == null) {
            initialIntentData = savedInstanceState.getString(KEY_INITIAL_INTENT)
        }

        handleIncomingIntent(intent, isInitial = true)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        initialIntentData?.let { outState.putString(KEY_INITIAL_INTENT, it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent, isInitial = false)
    }

    private fun handleIncomingIntent(intent: Intent?, isInitial: Boolean) {
        if (intent == null) return
        try {
            val action = intent.action
            val data: Uri? = intent.data
            var parsedPayload: String? = null

            if (Intent.ACTION_VIEW == action && data != null) {
                parsedPayload = data.toString()
                Log.d(TAG, "Incoming audio file intent: $parsedPayload")
            } else if ("android.media.action.MEDIA_PLAY_FROM_SEARCH" == action) {
                val query = intent.getStringExtra("query") ?: ""
                parsedPayload = "search:$query"
            }

            if (parsedPayload != null) {
                if (isInitial) {
                    initialIntentData = parsedPayload
                } else if (isEngineConnected) {
                    runOnUiThread {
                        intentChannel?.invokeMethod("onNewIntent", parsedPayload)
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "handleIncomingIntent notice: ${e.message}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        isEngineConnected = true
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        try {
            media3Bridge = LotusMedia3Bridge(messenger, applicationContext)
        } catch (e: Exception) {
            Log.w(TAG, "LotusMedia3Bridge registration notice: ${e.message}")
        }

        try {
            audioFxController = LotusAudioFxController.registerWith(messenger, applicationContext)
        } catch (e: Exception) {
            Log.w(TAG, "AudioFx notice: ${e.message}")
        }

        try {
            tagEditorController = LotusTagEditorController.registerWith(messenger, applicationContext) { this }
        } catch (e: Exception) {
            Log.w(TAG, "Primary tag controller notice: ${e.message}")
            setupTagEditorFallbackChannel(flutterEngine)
        }

        try {
            fileDeleterController = LotusFileDeleterController.registerWith(messenger, applicationContext) { this }
        } catch (e: Exception) {
            Log.w(TAG, "Deleter notice: ${e.message}")
        }

        try {
            flutterEngine.plugins.add(ArtworkCachePlugin())
        } catch (e: Exception) {
            Log.w(TAG, "ArtworkCachePlugin registration notice: ${e.message}")
        }

        intentChannel = MethodChannel(messenger, INTENT_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialIntent" -> {
                        result.success(initialIntentData)
                        initialIntentData = null
                    }
                    "moveToBackground" -> {
                        moveTaskToBack(true)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        permissionChannel = MethodChannel(messenger, PERMISSION_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestDeferredPermissions" -> requestDevicePermissionsExplicit(result)
                    "checkPermissions" -> result.success(hasAllPermissions())
                    else -> result.notImplemented()
                }
            }
        }

        dspFallbackChannel = MethodChannel(messenger, "com.souljalazian.lotus_player/dsp").apply {
            setMethodCallHandler { _, result -> result.success(true) }
        }
        playbackFallbackChannel = MethodChannel(messenger, "com.souljalazian.lotus_player/playback").apply {
            setMethodCallHandler { _, result -> result.success(true) }
        }

        updaterChannel = MethodChannel(messenger, "com.souljalazian.lotus_player/updater").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath.isNullOrBlank()) {
                            result.error("INVALID_PATH", "File path cannot be null or empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(filePath)
                            if (!file.exists()) {
                                result.error("FILE_NOT_FOUND", "APK file does not exist at $filePath", null)
                                return@setMethodCallHandler
                            }
                            val uri = FileProvider.getUriForFile(
                                this@MainActivity,
                                "com.souljalazian.lotus_player.fileprovider",
                                file
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to launch installer intent: ${e.message}", e)
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    }
                    "getAppInfo" -> {
                        try {
                            val pInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
                            } else {
                                @Suppress("DEPRECATION")
                                packageManager.getPackageInfo(packageName, 0)
                            }
                            val versionName = pInfo.versionName ?: "3.2.2"
                            val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                pInfo.longVersionCode
                            } else {
                                @Suppress("DEPRECATION")
                                pInfo.versionCode.toLong()
                            }
                            result.success(mapOf(
                                "version" to versionName,
                                "buildNumber" to versionCode
                            ))
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to query packageInfo: ${e.message}")
                            result.success(mapOf(
                                "version" to "3.2.2",
                                "buildNumber" to 422L
                            ))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        isEngineConnected = false

        pendingPermissionResult?.let { result ->
            try { result.success(false) } catch (_: Exception) {}
        }
        pendingPermissionResult = null
        isRequestingPermissions.set(false)

        intentChannel?.setMethodCallHandler(null)
        permissionChannel?.setMethodCallHandler(null)
        dspFallbackChannel?.setMethodCallHandler(null)
        playbackFallbackChannel?.setMethodCallHandler(null)

        intentChannel = null
        permissionChannel = null
        dspFallbackChannel = null
        playbackFallbackChannel = null

        try { media3Bridge?.dispose() } catch (_: Exception) {}
        try { LotusAudioFxController.detach() } catch (_: Exception) {}

        media3Bridge = null
        audioFxController = null
        tagEditorController = null
        fileDeleterController = null

        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        isEngineConnected = false
        if (activeInstance?.get() === this) {
            activeInstance = null
        }

        pendingPermissionResult?.let { result ->
            try { result.success(false) } catch (_: Exception) {}
        }
        pendingPermissionResult = null
        isRequestingPermissions.set(false)

        try {
            backgroundExecutor.shutdown()
            if (!backgroundExecutor.awaitTermination(300, TimeUnit.MILLISECONDS)) {
                backgroundExecutor.shutdownNow()
            }
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        } catch (_: Exception) {
            backgroundExecutor.shutdownNow()
        }

        super.onDestroy()
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        when (level) {
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_MODERATE,
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW,
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL -> {
                Log.w(TAG, "Memory pressure: level $level")
            }
            ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN -> {
                Log.d(TAG, "UI hidden — app backgrounded")
            }
            ComponentCallbacks2.TRIM_MEMORY_BACKGROUND,
            ComponentCallbacks2.TRIM_MEMORY_MODERATE,
            ComponentCallbacks2.TRIM_MEMORY_COMPLETE -> {
                Log.d(TAG, "Background trim: level $level")
            }
        }
    }

    private fun hasAllPermissions(): Boolean {
        return try {
            val hasAudio: Boolean =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.READ_MEDIA_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                } else {
                    val read = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.READ_EXTERNAL_STORAGE
                    ) == PackageManager.PERMISSION_GRANTED
                    val write = Build.VERSION.SDK_INT > Build.VERSION_CODES.Q ||
                            ContextCompat.checkSelfPermission(
                                this,
                                Manifest.permission.WRITE_EXTERNAL_STORAGE
                            ) == PackageManager.PERMISSION_GRANTED
                    read && write
                }

            val hasNotification: Boolean =
                Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                        ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.POST_NOTIFICATIONS
                        ) == PackageManager.PERMISSION_GRANTED

            hasAudio && hasNotification
        } catch (_: Exception) {
            true
        }
    }

    private fun requestDevicePermissionsExplicit(result: MethodChannel.Result) {
        if (!isRequestingPermissions.compareAndSet(false, true)) {
            Log.d(TAG, "Permission request already in progress — skipping")
            return
        }

        try {
            pendingPermissionResult?.let { oldResult ->
                try { oldResult.success(false) } catch (_: Exception) {}
            }
            pendingPermissionResult = result

            val permissionsNeeded = mutableListOf<String>()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                if (ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.READ_MEDIA_AUDIO
                    ) != PackageManager.PERMISSION_GRANTED
                ) {
                    permissionsNeeded.add(Manifest.permission.READ_MEDIA_AUDIO)
                }
                if (ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.POST_NOTIFICATIONS
                    ) != PackageManager.PERMISSION_GRANTED
                ) {
                    permissionsNeeded.add(Manifest.permission.POST_NOTIFICATIONS)
                }
            } else {
                if (ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.READ_EXTERNAL_STORAGE
                    ) != PackageManager.PERMISSION_GRANTED
                ) {
                    permissionsNeeded.add(Manifest.permission.READ_EXTERNAL_STORAGE)
                }
                if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.Q &&
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.WRITE_EXTERNAL_STORAGE
                    ) != PackageManager.PERMISSION_GRANTED
                ) {
                    permissionsNeeded.add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                }
            }

            if (permissionsNeeded.isNotEmpty()) {
                ActivityCompat.requestPermissions(
                    this,
                    permissionsNeeded.toTypedArray(),
                    PERMISSION_REQUEST_CODE
                )
            } else {
                pendingPermissionResult = null
                result.success(true)
                isRequestingPermissions.set(false)
            }
        } catch (e: Exception) {
            Log.w(TAG, "requestDevicePermissionsExplicit notice: ${e.message}")
            pendingPermissionResult = null
            try { result.success(true) } catch (_: Exception) {}
            isRequestingPermissions.set(false)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        try {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        } catch (e: Exception) {
            Log.w(TAG, "Permission result notice: ${e.message}")
        }

        if (requestCode == PERMISSION_REQUEST_CODE) {
            val allGranted = grantResults.isNotEmpty() &&
                    grantResults.all { it == PackageManager.PERMISSION_GRANTED }

            pendingPermissionResult?.let { result ->
                try {
                    result.success(allGranted)
                } catch (e: Exception) {
                    Log.w(TAG, "Permission result delivery notice: ${e.message}")
                }
            }
            pendingPermissionResult = null
            isRequestingPermissions.set(false)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        try {
            if (tagEditorController?.handleActivityResult(requestCode, resultCode) == true) {
                return
            }
        } catch (e: Exception) {
            Log.w(TAG, "tagEditorController onActivityResult notice: ${e.message}")
        }

        try {
            if (fileDeleterController?.handleActivityResult(requestCode, resultCode, data) == true) {
                return
            }
        } catch (e: Exception) {
            Log.w(TAG, "fileDeleterController onActivityResult notice: ${e.message}")
        }
    }

    private fun setupTagEditorFallbackChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.souljalazian.lotus_player/media_scanner"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFile" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    if (filePath.isNotEmpty()) {
                        val engineAlive = isEngineConnected
                        MediaScannerConnection.scanFile(
                            applicationContext,
                            arrayOf(filePath),
                            null
                        ) { _, uri ->
                            if (engineAlive && isEngineConnected) {
                                runOnUiThread {
                                    try {
                                        result.success(uri != null)
                                    } catch (e: Exception) {
                                        Log.w(TAG, "scanFile result delivery notice: ${e.message}")
                                    }
                                }
                            }
                        }
                    } else {
                        result.success(false)
                    }
                }

                "updateMediaStoreTags" -> {
                    backgroundExecutor.execute {
                        try {
                            val filePath = call.argument<String>("filePath") ?: ""
                            val songId = (call.argument<Number>("songId"))?.toLong() ?: 0L
                            val title = call.argument<String>("title") ?: ""
                            val artist = call.argument<String>("artist") ?: ""
                            val album = call.argument<String>("album") ?: ""
                            val year = call.argument<String>("year") ?: ""

                            val cv = ContentValues().apply {
                                if (title.isNotEmpty()) put(MediaStore.Audio.Media.TITLE, title)
                                if (artist.isNotEmpty()) put(MediaStore.Audio.Media.ARTIST, artist)
                                if (album.isNotEmpty()) put(MediaStore.Audio.Media.ALBUM, album)
                                year.toIntOrNull()?.let { put(MediaStore.Audio.Media.YEAR, it) }
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                    put(MediaStore.Audio.Media.IS_PENDING, 0)
                                }
                            }

                            if (songId > 0) {
                                val targetUri = ContentUris.withAppendedId(
                                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                                    songId
                                )
                                contentResolver.update(targetUri, cv, null, null)
                            } else if (filePath.isNotEmpty()) {
                                val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                                @Suppress("DEPRECATION")
                                contentResolver.update(
                                    uri,
                                    cv,
                                    "${MediaStore.Audio.Media.DATA}=?",
                                    arrayOf(filePath)
                                )
                            }

                            deliverResultOnUiThread(result) { it.success(true) }
                        } catch (e: Exception) {
                            deliverResultOnUiThread(result) {
                                it.error("TAG_ERROR", e.message, null)
                            }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private inline fun deliverResultOnUiThread(
        result: MethodChannel.Result,
        crossinline action: (MethodChannel.Result) -> Unit
    ) {
        if (!isEngineConnected) return
        runOnUiThread {
            if (isEngineConnected) {
                try {
                    action(result)
                } catch (e: Exception) {
                    Log.w(TAG, "Result delivery notice: ${e.message}")
                }
            }
        }
    }
}