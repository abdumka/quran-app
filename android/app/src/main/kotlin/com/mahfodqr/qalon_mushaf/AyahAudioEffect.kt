package com.mahfodqr.qalon_mushaf

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor.AudioFormat
import androidx.media3.common.audio.AudioProcessor.UnhandledAudioFormatException
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.tanh

/**
 * The «صدى / غرفة / قاعة» of an ayah video: space added around the reciter's
 * own voice. Pitch and speed are never touched; nothing else is mixed in.
 *
 * Runs once over the whole recitation (a composition-level effect), so a
 * reverb tail carries across ayah boundaries and rings out into the closing
 * card's silence instead of being cut at each file.
 *
 * Every number comes from the server (`share_video` content item), so the
 * strength of each effect can be tuned without a release:
 *
 *   echo:   {"type": "echo", "taps": [[delayMs, gain], ...], "dry": 1.0}
 *   reverb: {"type": "reverb", "room": 0..1, "damping": 0..1,
 *            "wet": 0..1, "dry": 0..1, "width": 0..1}
 */
@UnstableApi
class AyahAudioEffect(params: Map<*, *>) : BaseAudioProcessor() {
    private val type = params["type"] as? String ?: "none"
    private val dry = num(params["dry"], 1.0).coerceIn(0.0, 1.5).toFloat()

    // echo
    private val taps: List<Pair<Double, Float>> =
        (params["taps"] as? List<*>)?.mapNotNull { t ->
            val l = t as? List<*> ?: return@mapNotNull null
            if (l.size < 2) return@mapNotNull null
            num(l[0], 0.0).coerceIn(10.0, 2000.0) to num(l[1], 0.0).coerceIn(0.0, 0.9).toFloat()
        } ?: emptyList()

    // reverb
    private val room = num(params["room"], 0.5).coerceIn(0.0, 0.98)
    private val damping = num(params["damping"], 0.5).coerceIn(0.0, 1.0)
    private val wet = num(params["wet"], 0.1).coerceIn(0.0, 1.0).toFloat()
    private val width = num(params["width"], 1.0).coerceIn(0.0, 1.0).toFloat()

    private var channels = 0
    private var sampleRate = 0
    private var echoLines: Array<FloatArray> = emptyArray()
    private var echoPos = 0
    private var echoDelays = IntArray(0)
    private var verbs: Array<Freeverb> = emptyArray()

    override fun onConfigure(inputAudioFormat: AudioFormat): AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) {
            throw UnhandledAudioFormatException(inputAudioFormat)
        }
        if (type != "echo" && type != "reverb") return AudioFormat.NOT_SET
        channels = inputAudioFormat.channelCount
        sampleRate = inputAudioFormat.sampleRate
        return inputAudioFormat
    }

    override fun onFlush() {
        if (channels <= 0) return
        when (type) {
            "echo" -> {
                echoDelays = IntArray(taps.size) { (taps[it].first * sampleRate / 1000.0).roundToInt() }
                val len = (echoDelays.maxOrNull() ?: 0) + 1
                echoLines = Array(channels) { FloatArray(len) }
                echoPos = 0
            }
            "reverb" -> {
                verbs = Array(channels) { c ->
                    Freeverb(sampleRate, if (c % 2 == 1) STEREO_SPREAD else 0, room, damping)
                }
            }
        }
    }

    override fun onReset() {
        echoLines = emptyArray()
        verbs = emptyArray()
        channels = 0
        sampleRate = 0
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val size = inputBuffer.remaining()
        if (size == 0) return
        val out = replaceOutputBuffer(size)
        val frames = size / (2 * channels)
        val x = FloatArray(channels)
        val y = FloatArray(channels)
        for (f in 0 until frames) {
            for (c in 0 until channels) x[c] = inputBuffer.short / 32768f
            when (type) {
                "echo" -> echo(x, y)
                else -> reverb(x, y)
            }
            for (c in 0 until channels) {
                out.putShort((limit(y[c]) * 32767f).roundToInt().coerceIn(-32768, 32767).toShort())
            }
        }
        // a partial frame (never expected) is passed through untouched
        while (inputBuffer.hasRemaining()) out.put(inputBuffer.get())
        out.flip()
    }

    private fun echo(x: FloatArray, y: FloatArray) {
        val len = echoLines.firstOrNull()?.size ?: 1
        for (c in 0 until channels) {
            val line = echoLines[c]
            var v = x[c] * dry
            for (i in taps.indices) {
                var p = echoPos - echoDelays[i]
                if (p < 0) p += len
                v += line[p] * taps[i].second
            }
            line[echoPos] = x[c]
            y[c] = v
        }
        echoPos = (echoPos + 1) % len
    }

    private fun reverb(x: FloatArray, y: FloatArray) {
        // Freeverb feeds both channels the same mono sum and spreads the two
        // tanks slightly apart; the wet signal is then crossed by [width].
        var mono = 0f
        for (c in 0 until channels) mono += x[c]
        mono = mono / channels * FIXED_GAIN
        if (channels == 1) {
            y[0] = x[0] * dry + verbs[0].process(mono) * wet * WET_SCALE
            return
        }
        val l = verbs[0].process(mono)
        val r = verbs[1].process(mono)
        val wet1 = wet * WET_SCALE * (width / 2f + 0.5f)
        val wet2 = wet * WET_SCALE * ((1f - width) / 2f)
        y[0] = x[0] * dry + l * wet1 + r * wet2
        y[1] = x[1] * dry + r * wet1 + l * wet2
        for (c in 2 until channels) y[c] = x[c] * dry
    }

    /** A soft knee above 0.9 instead of hard clipping when echo adds up. */
    private fun limit(v: Float): Float {
        val a = abs(v)
        if (a <= KNEE) return v
        val s = KNEE + (1f - KNEE) * tanh((a - KNEE) / (1f - KNEE))
        return if (v < 0) -s else s
    }

    private class Freeverb(rate: Int, spread: Int, room: Double, damping: Double) {
        private val scale = rate / 44100.0
        private val combs = COMB_TUNING.map { Comb(((it + spread) * scale).roundToInt().coerceAtLeast(1)) }
        private val allpasses = ALLPASS_TUNING.map { Allpass(((it + spread) * scale).roundToInt().coerceAtLeast(1)) }

        init {
            val feedback = (room * 0.28 + 0.7).toFloat()
            val damp1 = (damping * 0.4).toFloat()
            for (c in combs) {
                c.feedback = feedback
                c.damp1 = damp1
                c.damp2 = 1f - damp1
            }
        }

        fun process(input: Float): Float {
            var out = 0f
            for (c in combs) out += c.process(input)
            for (a in allpasses) out = a.process(out)
            return out
        }
    }

    private class Comb(size: Int) {
        private val buf = FloatArray(size)
        private var idx = 0
        private var store = 0f
        var feedback = 0.84f
        var damp1 = 0.2f
        var damp2 = 0.8f

        fun process(x: Float): Float {
            val out = buf[idx]
            store = out * damp2 + store * damp1
            buf[idx] = x + store * feedback
            if (++idx >= buf.size) idx = 0
            return out
        }
    }

    private class Allpass(size: Int) {
        private val buf = FloatArray(size)
        private var idx = 0

        fun process(x: Float): Float {
            val b = buf[idx]
            val out = -x + b
            buf[idx] = x + b * 0.5f
            if (++idx >= buf.size) idx = 0
            return out
        }
    }

    companion object {
        private const val KNEE = 0.9f
        private const val FIXED_GAIN = 0.015f
        private const val WET_SCALE = 3f
        private const val STEREO_SPREAD = 23
        private val COMB_TUNING = intArrayOf(1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617)
        private val ALLPASS_TUNING = intArrayOf(556, 441, 341, 225)

        private fun num(v: Any?, fallback: Double): Double = when (v) {
            is Number -> v.toDouble().let { if (it.isFinite()) it else fallback }
            else -> fallback
        }

        /** Whether [params] asks for any processing at all. */
        fun isActive(params: Map<*, *>?): Boolean {
            val t = params?.get("type") as? String
            return t == "echo" || t == "reverb"
        }
    }
}
