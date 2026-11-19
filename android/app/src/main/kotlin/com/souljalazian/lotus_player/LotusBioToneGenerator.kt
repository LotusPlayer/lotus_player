package com.souljalazian.lotus_player

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Process
import android.util.Log
import java.util.Random
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sin

// ==============================================================================
// LOTUS BIO TONE GENERATOR - BALANCED 528HZ SINGING-BOWL BLOOM + PINK AIR BED
// ==============================================================================

class LotusBioToneGenerator {

    companion object {
        private const val TAG = "LotusBioTone"
        // 24 kHz (was 48 kHz): the bed only carries a 528 Hz carrier + pink noise
        // rolled off at ~2.5 kHz, so 24 kHz is more than enough and halves the
        // per-sample math (3 sin/cos + 12 filter ops) — directly cuts this thread's
        // CPU in half. The three one-pole filter coefficients below were rescaled
        // by 1 - exp(-2π·fc/24000) so their cutoff frequencies are unchanged.
        private const val SAMPLE_RATE = 24_000
        private const val BLOCK_FRAMES = 2048
        private const val BASE_CARRIER_HZ = 528.0
        private const val TWO_PI = 2.0 * Math.PI

        private const val MAX_TONE_GAIN = 0.045f
        private const val MAX_NOISE_GAIN = 0.050f
    }

    @Volatile var toneBlend: Float = 0.35f
    @Volatile var isochronicDepth: Float = 0.35f
    @Volatile var noiseMask: Float = 0.15f
    @Volatile var pulseHz: Float = 6.0f

    @Volatile private var running = false
    private var thread: Thread? = null

    @Synchronized
    fun start() {
        running = true
        if (thread != null) return
        thread = Thread({ renderLoop() }, "LotusBioTone").apply {
            isDaemon = true
            start()
        }
    }

    fun stop() {
        running = false
    }

    private fun buildTrack(): AudioTrack? {
        return try {
            val minBuf = AudioTrack.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_OUT_STEREO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            if (minBuf <= 0) return null

            val frameBytes = 4
            val bufBytes = max(minBuf * 2, BLOCK_FRAMES * frameBytes * 4)

            AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(SAMPLE_RATE)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .build()
                )
                .setBufferSizeInBytes(bufBytes)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
        } catch (e: Exception) {
            Log.w(TAG, "AudioTrack init error: ${e.message}")
            null
        }
    }

    private fun renderLoop() {
        try {
            // Background priority (was AUDIO): the bed is mixed at ~5% gain, so
            // an occasional underrun is inaudible; yielding to the UI thread is
            // what keeps shade-pull / unlock animations smooth.
            Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
        } catch (_: Exception) {}

        val track = buildTrack()
        if (track == null || track.state != AudioTrack.STATE_INITIALIZED) {
            try { track?.release() } catch (_: Exception) {}
            synchronized(this) { thread = null }
            return
        }

        try {
            val buf = ShortArray(BLOCK_FRAMES * 2)
            val rnd = Random()

            var lowPhase = 0.0      // 132 Hz warm root
            var midPhase = 0.0      // 264 Hz octave warmth
            var bowlPhase = 0.0     // 528 Hz soft singing-bowl bloom
            var bowlEnvPhase = 0.0  // ~9s bloom envelope so 528 Hz never drones like a beep
            var pulsePhase = 0.0
            var surfLfoPhase = 0.0

            var master = 0f
            var smoothToneGain = 0f
            var smoothNoiseGain = 0f
            var smoothPulseHz = 6.0f

            // ~485 Hz low-pass for silky smooth pad
            var lpTone = 0f

            // Stereo Kellet Pink Noise state + rumble blocker (~155 Hz HP) + air softener (~3 kHz LP)
            var b0L = 0f; var b1L = 0f; var b2L = 0f
            var b0R = 0f; var b1R = 0f; var b2R = 0f
            var prevPinkL = 0f; var hpNoiseL = 0f; var lpAirL = 0f
            var prevPinkR = 0f; var hpNoiseR = 0f; var lpAirR = 0f

            val lowInc = TWO_PI * (BASE_CARRIER_HZ * 0.25) / SAMPLE_RATE // 132 Hz
            val midInc = TWO_PI * (BASE_CARRIER_HZ * 0.50) / SAMPLE_RATE // 264 Hz
            val bowlInc = TWO_PI * BASE_CARRIER_HZ / SAMPLE_RATE         // 528 Hz
            val bowlEnvInc = TWO_PI * 0.11 / SAMPLE_RATE                 // ~9.1s soft bloom cycle
            val surfLfoInc = TWO_PI * 0.14 / SAMPLE_RATE                 // ~7.1s gentle air swell

            track.play()

            while (true) {
                val wantRun = running
                if (!wantRun && master <= 0.0005f) {
                    var exit = false
                    synchronized(this) {
                        if (!running) {
                            thread = null
                            exit = true
                        }
                    }
                    if (exit) break
                }

                val masterTarget = if (wantRun) 1f else 0f
                val toneNorm = toneBlend.coerceIn(0f, 1f)
                val noiseNorm = noiseMask.coerceIn(0f, 1f)

                val toneTarget = (toneNorm * toneNorm) * MAX_TONE_GAIN
                val noiseTarget = (noiseNorm * noiseNorm) * MAX_NOISE_GAIN
                val targetPulseHz = pulseHz.coerceIn(0.5f, 20.0f)

                val breathDepth = (isochronicDepth.coerceIn(0f, 1f) * 0.12f).toDouble()

                var idx = 0
                for (n in 0 until BLOCK_FRAMES) {
                    master += (masterTarget - master) * 0.0005f
                    smoothToneGain += (toneTarget - smoothToneGain) * 0.001f
                    smoothNoiseGain += (noiseTarget - smoothNoiseGain) * 0.001f
                    smoothPulseHz += (targetPulseHz - smoothPulseHz) * 0.0008f

                    // Gentle symmetric breathing
                    val pulseInc = TWO_PI * (smoothPulseHz / SAMPLE_RATE)
                    val breath = 1.0 - (breathDepth * 0.5 * (1.0 - cos(pulsePhase)))
                    pulsePhase += pulseInc
                    if (pulsePhase >= TWO_PI) pulsePhase -= TWO_PI

                    // Soft singing-bowl swell for 528 Hz (fades smoothly to 0 between blooms)
                    val bowlEnv = (0.5 * (1.0 - cos(bowlEnvPhase))).pow(2.5)
                    bowlEnvPhase += bowlEnvInc
                    if (bowlEnvPhase >= TWO_PI) bowlEnvPhase -= TWO_PI

                    val warmPad = (sin(lowPhase) * 0.55) +
                            (sin(midPhase) * 0.35) +
                            (sin(bowlPhase) * 0.25 * bowlEnv)

                    val rawTone = (warmPad * 0.70 * breath).toFloat()
                    lpTone += 0.12f * (rawTone - lpTone)
                    val balancedTone = lpTone * smoothToneGain

                    lowPhase = (lowPhase + lowInc).let { if (it >= TWO_PI) it - TWO_PI else it }
                    midPhase = (midPhase + midInc).let { if (it >= TWO_PI) it - TWO_PI else it }
                    bowlPhase = (bowlPhase + bowlInc).let { if (it >= TWO_PI) it - TWO_PI else it }

                    // Pink-weighted airy ambient bed (stereo decorrelated, equal L/R level)
                    val swell = 0.65f + 0.35f * (0.5f * (1.0f + cos(surfLfoPhase).toFloat()))
                    surfLfoPhase += surfLfoInc
                    if (surfLfoPhase >= TWO_PI) surfLfoPhase -= TWO_PI

                    val wL = rnd.nextFloat() * 2f - 1f
                    b0L = 0.99765f * b0L + wL * 0.0990460f
                    b1L = 0.96300f * b1L + wL * 0.2965164f
                    b2L = 0.57000f * b2L + wL * 1.0526913f
                    val pinkL = (b0L + b1L + b2L + wL * 0.1848f) * 0.16f
                    hpNoiseL = 0.96f * (hpNoiseL + pinkL - prevPinkL)
                    prevPinkL = pinkL
                    lpAirL += 0.48f * (hpNoiseL - lpAirL)

                    val wR = rnd.nextFloat() * 2f - 1f
                    b0R = 0.99765f * b0R + wR * 0.0990460f
                    b1R = 0.96300f * b1R + wR * 0.2965164f
                    b2R = 0.57000f * b2R + wR * 1.0526913f
                    val pinkR = (b0R + b1R + b2R + wR * 0.1848f) * 0.16f
                    hpNoiseR = 0.96f * (hpNoiseR + pinkR - prevPinkR)
                    prevPinkR = pinkR
                    lpAirR += 0.48f * (hpNoiseR - lpAirR)

                    val bedL = lpAirL * smoothNoiseGain * swell
                    val bedR = lpAirR * smoothNoiseGain * swell

                    val outL = ((balancedTone + bedL) * master).coerceIn(-0.95f, 0.95f)
                    val outR = ((balancedTone + bedR) * master).coerceIn(-0.95f, 0.95f)

                    buf[idx++] = (outL * 32767f).toInt().toShort()
                    buf[idx++] = (outR * 32767f).toInt().toShort()
                }

                var offset = 0
                var fatalWriteError = false
                while (offset < buf.size && (running || master > 0.0005f)) {
                    val written = track.write(buf, offset, buf.size - offset)
                    if (written < 0) {
                        Log.w(TAG, "AudioTrack write error: $written")
                        fatalWriteError = true
                        break
                    } else if (written == 0) {
                        Thread.sleep(5)
                    } else {
                        offset += written
                    }
                }
                if (fatalWriteError) break
            }
        } catch (e: Exception) {
            Log.w(TAG, "Render loop notice: ${e.message}")
        } finally {
            synchronized(this) {
                if (thread === Thread.currentThread()) {
                    thread = null
                }
            }
            try { track.stop() } catch (_: Exception) {}
            try { track.flush() } catch (_: Exception) {}
            try { track.release() } catch (_: Exception) {}
        }
    }
}