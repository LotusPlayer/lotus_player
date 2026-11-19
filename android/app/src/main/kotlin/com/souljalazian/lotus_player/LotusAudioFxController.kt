package com.souljalazian.lotus_player

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.Virtualizer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadFactory
import kotlin.math.max

// ==============================================================================
// LOTUS AUDIO FX CONTROLLER - HARDWARE EQUALIZER + AUX EFFECTS + BIO-ENGINE
// ==============================================================================

class LotusAudioFxController private constructor(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "LotusAudioFx"
        const val CHANNEL_DSP = "com.souljalazian.lotus_player/dsp_equalizer"
        const val CHANNEL_EFFECTS = "com.souljalazian.lotus_player/audio_effects"
        private const val EFFECT_PRIORITY = 0

        private const val TONE_MAX = 0.70f
        private const val ISO_MAX = 0.55f
        private const val NOISE_MAX = 0.40f

        private const val RETRY_FAILED_ATTACH_MS = 4_000L
        private const val DEVICE_REBIND_DEBOUNCE_MS = 350L

        @Volatile
        private var instance: LotusAudioFxController? = null

        private var dspChannel: MethodChannel? = null
        private var effectsChannel: MethodChannel? = null

        fun ensureCreated(context: Context): LotusAudioFxController {
            return instance ?: synchronized(this) {
                instance ?: LotusAudioFxController(context.applicationContext)
                    .also { instance = it }
            }
        }

        fun notifyPlaybackActive(active: Boolean) {
            instance?.let { ctrl ->
                ctrl.playbackActive = active
                // Skip unnecessary work when the Bio-Engine isn't active/running,
                // and never block the main thread inside Player.Listener.
                if (ctrl.isMoodBioEngineActive || ctrl.bioWasStarted) {
                    ctrl.safeExecute { ctrl.updateBioGenerator() }
                }
            }
        }

        fun registerWith(
            messenger: BinaryMessenger,
            context: Context
        ): LotusAudioFxController {
            val controller = ensureCreated(context)
            controller.isDetached = false

            dspChannel = MethodChannel(messenger, CHANNEL_DSP).apply {
                setMethodCallHandler(controller)
            }
            effectsChannel = MethodChannel(messenger, CHANNEL_EFFECTS).apply {
                setMethodCallHandler(controller)
            }

            return controller
        }

        fun notifySessionId(sessionId: Int) {
            if (sessionId <= 0) return
            instance?.let { ctrl ->
                if (sessionId == ctrl.currentSessionId) return
                ctrl.safeExecute {
                    ctrl.attachToAudioSession(sessionId, force = false)
                }
            }
        }

        fun detach() {
            dspChannel?.setMethodCallHandler(null)
            effectsChannel?.setMethodCallHandler(null)
            dspChannel = null
            effectsChannel = null
            instance?.isDetached = true
        }

        fun releaseEffects() {
            val ctrl = instance ?: return
            ctrl.playbackActive = false
            ctrl.safeExecute {
                if (ctrl.bioWasStarted) {
                    try { ctrl.bioGenerator.stop() } catch (_: Exception) {}
                    ctrl.bioWasStarted = false
                }
                ctrl.releaseEffectsInternal()
            }
        }
    }

    private val dspExecutor: ExecutorService = Executors.newSingleThreadExecutor(
        ThreadFactory { runnable ->
            Thread(runnable, "LotusDspWorker").apply {
                isDaemon = true
                priority = Thread.NORM_PRIORITY
            }
        }
    )

    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioManager: AudioManager? =
        context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

    @Volatile
    private var isDetached: Boolean = false

    @Volatile
    private var currentSessionId: Int = 0

    @Volatile
    private var lastAttachAttemptMs: Long = 0L

    private var equalizer: Equalizer? = null

    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null

    @Volatile private var cachedBassStrength: Short = 0
    @Volatile private var cachedVirtualizerStrength: Short = 0
    @Volatile private var cachedLoudnessMb: Int = 0
    private var appliedBass: Short? = null
    private var appliedVirtualizer: Short? = null
    private var appliedLoudness: Int? = null

    private val appliedBandLevels = mutableMapOf<Short, Short>()
    private var appliedEqEnabled: Boolean? = null

    @Volatile
    private var cachedNumBands: Short = 0
    private var cachedMinLevel: Short = -1500
    private var cachedMaxLevel: Short = 1500
    private var cachedCenterFreqs: IntArray = intArrayOf()

    @Volatile
    private var isEnabled: Boolean = true
    private val cachedBandGains = mutableMapOf<Short, Short>()

    @Volatile
    private var isMoodBioEngineActive: Boolean = false
    @Volatile
    private var cachedToneBlendRatio: Float = 0.35f
    @Volatile
    private var cachedIsochronicDepth: Float = 0.40f
    @Volatile
    private var cachedNoiseMaskStrength: Float = 0.18f
    @Volatile
    private var cachedPulseFrequency: Double = 6.0

    private var deviceCallback: AudioDeviceCallback? = null
    private val deviceRebindRunnable = Runnable { onAudioRouteChanged() }

    private val bioGenerator = LotusBioToneGenerator()

    @Volatile
    private var playbackActive: Boolean = false

    @Volatile
    private var bioWasStarted: Boolean = false

    @Synchronized
    private fun updateBioGenerator() {
        bioGenerator.toneBlend = (cachedToneBlendRatio * TONE_MAX).coerceIn(0.0f, TONE_MAX)
        bioGenerator.isochronicDepth = (cachedIsochronicDepth * ISO_MAX).coerceIn(0.0f, ISO_MAX)
        bioGenerator.noiseMask = (cachedNoiseMaskStrength * NOISE_MAX).coerceIn(0.0f, NOISE_MAX)
        bioGenerator.pulseHz = cachedPulseFrequency.toFloat()

        if (isMoodBioEngineActive && playbackActive) {
            bioGenerator.start()
            bioWasStarted = true
        } else if (bioWasStarted) {
            bioGenerator.stop()
            bioWasStarted = false
        }
    }

    init {
        registerDeviceCallback()
    }

    private fun safeExecute(task: () -> Unit) {
        try {
            if (!dspExecutor.isShutdown && !dspExecutor.isTerminated) {
                dspExecutor.execute {
                    try {
                        task()
                    } catch (e: Exception) {
                        Log.w(TAG, "DSP task error: ${e.message}")
                    }
                }
            }
        } catch (e: RejectedExecutionException) {
            Log.w(TAG, "DSP worker rejected: ${e.message}")
        }
    }

    private fun safeResult(result: MethodChannel.Result, block: () -> Unit) {
        if (isDetached) return
        mainHandler.post {
            if (isDetached) return@post
            try { block() } catch (e: Exception) { Log.w(TAG, "Result notice: ${e.message}") }
        }
    }

    private fun ensureSessionThenDispatch(requestedSessionId: Int) {
        val sessionId = if (requestedSessionId > 0) requestedSessionId else currentSessionId
        safeExecute {
            val needsRebuild = sessionId > 0 && (
                    sessionId != currentSessionId ||
                            (equalizer == null &&
                                    System.currentTimeMillis() - lastAttachAttemptMs > RETRY_FAILED_ATTACH_MS)
                    )
            if (needsRebuild) {
                attachToAudioSession(sessionId, force = true)
            } else {
                dispatchActiveEffectChain()
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (isDetached) {
            result.error("DETACHED", "Controller is detaching", null)
            return
        }

        when (call.method) {
            "applyDspSettings" -> {
                try {
                    val sessionId = call.argument<Int>("audioSessionId") ?: 0
                    val enabled = call.argument<Boolean>("enabled") ?: isEnabled
                    val gains = call.argument<List<Int>?>("bandGainsMilliBels")

                    isEnabled = enabled

                    synchronized(cachedBandGains) {
                        gains?.forEachIndexed { index, gain ->
                            cachedBandGains[index.toShort()] = gain.toShort()
                        }
                    }

                    ensureSessionThenDispatch(sessionId)
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "DSP apply failed: ${e.message}")
                    result.error("DSP_ERROR", e.message, null)
                }
            }

            "setEqualizerEnabled" -> {
                isEnabled = call.argument<Boolean>("enabled") ?: isEnabled
                ensureSessionThenDispatch(call.argument<Int>("audioSessionId") ?: 0)
                result.success(true)
            }

            "applyMoodBioEngine" -> {
                try {
                    isMoodBioEngineActive = call.argument<Boolean>("enabled") ?: false
                    cachedToneBlendRatio = (call.argument<Double>("toneBlend")?.toFloat() ?: cachedToneBlendRatio).coerceIn(0.0f, 1.0f)
                    cachedIsochronicDepth = (call.argument<Double>("isochronicDepth")?.toFloat() ?: cachedIsochronicDepth).coerceIn(0.0f, 1.0f)
                    cachedNoiseMaskStrength = (call.argument<Double>("noiseMask")?.toFloat() ?: cachedNoiseMaskStrength).coerceIn(0.0f, 1.0f)
                    cachedPulseFrequency = call.argument<Double>("pulseFrequency") ?: cachedPulseFrequency
                    call.argument<Boolean>("playbackActive")?.let { playbackActive = it }

                    safeExecute {
                        updateBioGenerator()
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.error("MOOD_BIO_ENGINE_ERROR", e.message, null)
                }
            }

            "setAuxEffects" -> {
                try {
                    cachedBassStrength = (call.argument<Int>("bassStrength") ?: cachedBassStrength.toInt()).coerceIn(0, 1000).toShort()
                    cachedVirtualizerStrength = (call.argument<Int>("virtualizerStrength") ?: cachedVirtualizerStrength.toInt()).coerceIn(0, 1000).toShort()
                    cachedLoudnessMb = (call.argument<Int>("loudnessMb") ?: cachedLoudnessMb).coerceIn(0, 1500)
                    safeExecute { dispatchAuxEffects() }
                    result.success(true)
                } catch (e: Exception) {
                    result.error("AUX_EFFECTS_ERROR", e.message, null)
                }
            }

            "setBioPlaybackActive" -> {
                playbackActive = call.argument<Boolean>("active") ?: false
                if (isMoodBioEngineActive || bioWasStarted) {
                    safeExecute { updateBioGenerator() }
                }
                result.success(true)
            }

            "attachAudioSession" -> {
                val sessionId = call.argument<Int>("audioSessionId") ?: 0
                val force = call.argument<Boolean>("force") ?: false
                if (sessionId > 0) {
                    safeExecute { attachToAudioSession(sessionId, force) }
                    result.success(true)
                } else {
                    result.success(false)
                }
            }

            "getEqualizerParameters" -> {
                if (cachedNumBands > 0) {
                    result.success(buildCachedSpecsMap())
                    return
                }
                safeExecute {
                    val params = getEqualizerSpecs()
                    safeResult(result) {
                        if (params != null) result.success(params)
                        else result.error("UNAVAILABLE", "Equalizer not ready", null)
                    }
                }
            }

            "setBandLevel" -> {
                val band = call.argument<Int>("band")?.toShort()
                val level = call.argument<Int>("level")?.toShort()
                if (band != null && level != null) {
                    val clamped = level.coerceIn(cachedMinLevel, cachedMaxLevel)
                    synchronized(cachedBandGains) {
                        cachedBandGains[band] = clamped
                    }
                    safeExecute {
                        dispatchActiveEffectChain()
                        safeResult(result) { result.success(true) }
                    }
                } else {
                    result.error("INVALID_ARGUMENTS", "Band or level missing", null)
                }
            }

            "release" -> {
                safeExecute {
                    if (bioWasStarted) {
                        try { bioGenerator.stop() } catch (_: Exception) {}
                        bioWasStarted = false
                    }
                    releaseEffectsInternal()
                    safeResult(result) { result.success(true) }
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun registerDeviceCallback() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || deviceCallback != null) return
        val am = audioManager ?: return
        val cb = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                scheduleRouteRebind()
            }

            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                scheduleRouteRebind()
            }
        }
        try {
            am.registerAudioDeviceCallback(cb, mainHandler)
            deviceCallback = cb
        } catch (e: Exception) {
            Log.w(TAG, "registerAudioDeviceCallback error: ${e.message}")
        }
    }

    private fun scheduleRouteRebind() {
        mainHandler.removeCallbacks(deviceRebindRunnable)
        mainHandler.postDelayed(deviceRebindRunnable, DEVICE_REBIND_DEBOUNCE_MS)
    }

    private fun onAudioRouteChanged() {
        val sid = currentSessionId
        if (sid > 0) {
            safeExecute { attachToAudioSession(sid, force = true) }
        }
        if (!isDetached) {
            try {
                dspChannel?.invokeMethod("onAudioDeviceChanged", null)
            } catch (e: Exception) {
                Log.w(TAG, "route notify error: ${e.message}")
            }
        }
    }

    @Synchronized
    fun attachToAudioSession(sessionId: Int, force: Boolean = false) {
        if (sessionId <= 0) return
        if (!force && sessionId == currentSessionId && equalizer != null) return

        Log.d(TAG, "Attaching effect chain to Session #$sessionId (force=$force)")
        releaseEffectsInternal()
        currentSessionId = sessionId
        lastAttachAttemptMs = System.currentTimeMillis()

        try {
            equalizer = Equalizer(EFFECT_PRIORITY, currentSessionId).apply {
                cachedNumBands = numberOfBands
                val range = bandLevelRange
                if (range.size >= 2 && range[0] < range[1]) {
                    cachedMinLevel = range[0]
                    cachedMaxLevel = range[1]
                }
                cachedCenterFreqs = IntArray(cachedNumBands.toInt()) { i ->
                    getCenterFreq(i.toShort())
                }
            }
            appliedEqEnabled = null
        } catch (e: Exception) {
            Log.e(TAG, "Equalizer init failed on session #$sessionId: ${e.message}")
            equalizer = null
        }

        bassBoost = tryCreate("BassBoost") { BassBoost(EFFECT_PRIORITY, currentSessionId) }
        virtualizer = tryCreate("Virtualizer") { Virtualizer(EFFECT_PRIORITY, currentSessionId) }
        loudnessEnhancer = tryCreate("LoudnessEnhancer") { LoudnessEnhancer(currentSessionId) }

        appliedBass = null
        appliedVirtualizer = null
        appliedLoudness = null

        dispatchActiveEffectChain()
        dispatchAuxEffects()
    }

    private inline fun <reified T : Any> tryCreate(name: String, factory: () -> T): T? {
        return try {
            factory()
        } catch (t: Throwable) {
            Log.e(TAG, "$name creation failed (session=$currentSessionId): ${t.message}. Device/ROM skipped.", t)
            null
        }
    }

    @Synchronized
    private fun dispatchActiveEffectChain() {
        val userGains: Map<Short, Short> = synchronized(cachedBandGains) { cachedBandGains.toMap() }

        try {
            val hasUserGain = isEnabled && userGains.values.any { it.toInt() != 0 }
            val shouldEnableEq = hasUserGain

            equalizer?.let { eq ->
                if (appliedEqEnabled != shouldEnableEq) {
                    eq.enabled = shouldEnableEq
                    appliedEqEnabled = shouldEnableEq
                }

                if (shouldEnableEq) {
                    val numBands = cachedNumBands.toInt()
                    val rawTargetGains = IntArray(numBands)

                    for (i in 0 until numBands) {
                        val band = i.toShort()
                        rawTargetGains[i] = (userGains[band] ?: 0).toInt()
                    }

                    val maxPositive = max(0, rawTargetGains.maxOrNull() ?: 0)
                    val headroom = if (maxPositive > 600) -(maxPositive / 4) else 0

                    for (i in 0 until numBands) {
                        val band = i.toShort()
                        val clamped = (rawTargetGains[i] + headroom)
                            .coerceIn(cachedMinLevel.toInt(), cachedMaxLevel.toInt())
                            .toShort()

                        if (appliedBandLevels[band] != clamped) {
                            eq.setBandLevel(band, clamped)
                            appliedBandLevels[band] = clamped
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Equalizer dispatch error: ${e.message}")
        }

        if (isMoodBioEngineActive || bioWasStarted) {
            updateBioGenerator()
        }
    }

    @Synchronized
    private fun dispatchAuxEffects() {
        try {
            bassBoost?.let { bb ->
                val targetStrength = cachedBassStrength.toInt().coerceIn(0, 1000).toShort()
                val shouldBeEnabled = targetStrength > 0
                if (bb.enabled != shouldBeEnabled) {
                    bb.enabled = shouldBeEnabled
                }
                if (shouldBeEnabled && appliedBass != targetStrength) {
                    bb.setStrength(targetStrength)
                    appliedBass = targetStrength
                }
            }

            virtualizer?.let { v ->
                val targetStrength = cachedVirtualizerStrength.toInt().coerceIn(0, 1000).toShort()
                val shouldBeEnabled = targetStrength > 0
                if (v.enabled != shouldBeEnabled) {
                    v.enabled = shouldBeEnabled
                }
                if (shouldBeEnabled && appliedVirtualizer != targetStrength) {
                    v.setStrength(targetStrength)
                    appliedVirtualizer = targetStrength
                }
            }

            loudnessEnhancer?.let { le ->
                val targetGain = cachedLoudnessMb.coerceIn(0, 1500)
                val shouldBeEnabled = targetGain > 0
                if (le.enabled != shouldBeEnabled) {
                    le.enabled = shouldBeEnabled
                }
                if (shouldBeEnabled && appliedLoudness != targetGain) {
                    le.setTargetGain(targetGain)
                    appliedLoudness = targetGain
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Aux effects dispatch error: ${e.message}")
        }
    }

    private fun buildCachedSpecsMap(): Map<String, Any> {
        val centerFreqsList = cachedCenterFreqs.toList()
        val currentLevelsList = mutableListOf<Int>()
        synchronized(cachedBandGains) {
            for (i in 0 until cachedNumBands) {
                currentLevelsList.add((cachedBandGains[i.toShort()] ?: 0).toInt())
            }
        }
        return mapOf(
            "numberOfBands" to cachedNumBands.toInt(),
            "minLevel" to cachedMinLevel.toInt(),
            "maxLevel" to cachedMaxLevel.toInt(),
            "centerFrequencies" to centerFreqsList,
            "currentLevels" to currentLevelsList
        )
    }

    private fun getEqualizerSpecs(): Map<String, Any>? {
        val eq = equalizer ?: return null
        return try {
            val numBands = eq.numberOfBands.toInt()
            cachedNumBands = eq.numberOfBands
            val bandRange = eq.bandLevelRange
            val minLvl = if (bandRange.size >= 2) bandRange[0].toInt() else -1500
            val maxLvl = if (bandRange.size >= 2) bandRange[1].toInt() else 1500

            val centerFreqs = mutableListOf<Int>()
            val currentLevels = mutableListOf<Int>()

            synchronized(cachedBandGains) {
                for (i in 0 until numBands) {
                    val band = i.toShort()
                    centerFreqs.add(eq.getCenterFreq(band))
                    val level = cachedBandGains[band] ?: 0.toShort()
                    currentLevels.add(level.toInt())
                }
            }

            mapOf(
                "numberOfBands" to numBands,
                "minLevel" to minLvl,
                "maxLevel" to maxLvl,
                "centerFrequencies" to centerFreqs,
                "currentLevels" to currentLevels
            )
        } catch (e: Exception) {
            null
        }
    }

    @Synchronized
    private fun releaseEffectsInternal() {
        try { equalizer?.enabled = false; equalizer?.release() } catch (_: Exception) {}
        try { bassBoost?.enabled = false; bassBoost?.release() } catch (_: Exception) {}
        try { virtualizer?.enabled = false; virtualizer?.release() } catch (_: Exception) {}
        try { loudnessEnhancer?.release() } catch (_: Exception) {}

        equalizer = null
        bassBoost = null
        virtualizer = null
        loudnessEnhancer = null
        currentSessionId = 0
        appliedBandLevels.clear()
        appliedEqEnabled = null
        appliedBass = null
        appliedVirtualizer = null
        appliedLoudness = null
    }
}