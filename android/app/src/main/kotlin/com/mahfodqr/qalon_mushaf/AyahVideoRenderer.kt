package com.mahfodqr.qalon_mushaf

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.SonicAudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import com.google.common.collect.ImmutableList
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * «فيديو الآية»: builds the MP4 on the phone, so nothing is uploaded and our
 * server does no work. Dart prepares everything that is drawn (one picture
 * per ayah group with the mushaf text, the surah title and the watermark, and
 * the closing card) and the audio clips; this class only puts them together
 * with Media3 Transformer, using the phone's hardware encoder:
 *
 *   sequence 1: the background clip, looping until the recitation ends;
 *   sequence 2: the recitation clips one after another, then the closing
 *               card's silence;
 *   composition effects: the pictures as a timed overlay, and the echo or
 *               reverb over the whole recitation ([AyahAudioEffect]).
 *
 * Channel `com.mahfodqr.qalon_mushaf/ayah_video`:
 *   isSupported -> Boolean
 *   render(args) -> {"path": String, "durationMs": Int}  (or an error)
 *   progress -> Double in 0..1, or null before it starts
 *   freeBytes -> Long, the free space of the cache folder (or null)
 *   cancel
 */
@UnstableApi
class AyahVideoRenderer(private val context: Context) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var transformer: Transformer? = null
    private var overlay: TimedOverlay? = null
    private var pending: MethodChannel.Result? = null
    private var totalUs = 0L
    private var cancelled = false
    private val progressHolder = ProgressHolder()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(true)
            "render" -> render(call.arguments as? Map<*, *>, result)
            "progress" -> result.success(progress())
            // Before a long video: is there room for it where it is made?
            "freeBytes" -> result.success(
                try {
                    android.os.StatFs(context.cacheDir.path).availableBytes
                } catch (_: Exception) {
                    null
                },
            )
            "cancel" -> {
                cancel()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun progress(): Double? {
        val t = transformer ?: return null
        val o = overlay
        if (o != null && totalUs > 0 && o.lastPtsUs > 0) {
            return (o.lastPtsUs.toDouble() / totalUs).coerceIn(0.0, 0.99)
        }
        return when (t.getProgress(progressHolder)) {
            Transformer.PROGRESS_STATE_AVAILABLE -> progressHolder.progress / 100.0
            else -> 0.0
        }
    }

    private fun cancel() {
        cancelled = true
        transformer?.cancel()
        transformer = null
        overlay = null
        pending?.error("cancelled", "cancelled", null)
        pending = null
    }

    private fun render(args: Map<*, *>?, result: MethodChannel.Result) {
        if (args == null) {
            result.error("bad_args", "no arguments", null)
            return
        }
        if (pending != null) cancel()
        cancelled = false
        pending = result
        // Probing file lengths can touch the network (a whole-surah file read
        // straight from the mirror), so it never runs on the main thread.
        io.execute {
            val plan = try {
                Plan.from(args, ::durationMs)
            } catch (e: Exception) {
                Log.w(TAG, "plan failed", e)
                main.post { finish(error = "plan: ${e.message}") }
                return@execute
            }
            main.post { if (!cancelled) start(plan) }
        }
    }

    private fun start(plan: Plan) {
        try {
            val audioItems = ArrayList<EditedMediaItem>()
            for (clip in plan.clips) {
                val builder = MediaItem.Builder().setUri(Uri.parse(clip.uri))
                if (clip.startMs != null || clip.endMs != null) {
                    val clipping = MediaItem.ClippingConfiguration.Builder()
                    clip.startMs?.let { clipping.setStartPositionMs(it) }
                    clip.endMs?.let { clipping.setEndPositionMs(it) }
                    builder.setClippingConfiguration(clipping.build())
                }
                audioItems += EditedMediaItem.Builder(builder.build()).setRemoveVideo(true).build()
            }
            if (plan.silenceUri != null) {
                audioItems += EditedMediaItem.Builder(MediaItem.fromUri(Uri.parse(plan.silenceUri)))
                    .setRemoveVideo(true)
                    .build()
            }

            // The pictures ride on the background item itself: in Media3
            // 1.4 a single video sequence ignores composition-level video
            // effects. Its frames carry the whole timeline's timestamps (the
            // loop offsets are added before effects run), so the overlay
            // still switches at the right moments on every pass.
            val timed = TimedOverlay(plan.overlays)
            overlay = timed
            totalUs = plan.totalUs
            val videoEffects = Effects(
                emptyList(),
                listOf(OverlayEffect(ImmutableList.of<TextureOverlay>(timed))),
            )
            val background = if (plan.backgroundIsImage) {
                EditedMediaItem.Builder(MediaItem.fromUri(Uri.parse(plan.backgroundUri)))
                    .setDurationUs(IMAGE_LOOP_US)
                    .setFrameRate(plan.fps)
                    .setEffects(videoEffects)
                    .build()
            } else {
                EditedMediaItem.Builder(MediaItem.fromUri(Uri.parse(plan.backgroundUri)))
                    .setRemoveAudio(true)
                    .setEffects(videoEffects)
                    .build()
            }

            // Some mirrors are 22-24 kHz; everything leaves at 44.1 kHz, and
            // the effect runs after the resampling.
            val audioProcessors = ArrayList<AudioProcessor>()
            audioProcessors += SonicAudioProcessor().apply { setOutputSampleRateHz(OUTPUT_RATE) }
            if (AyahAudioEffect.isActive(plan.effect)) audioProcessors += AyahAudioEffect(plan.effect!!)
            val composition = Composition.Builder(
                listOf(
                    EditedMediaItemSequence(listOf(background), /* isLooping= */ true),
                    EditedMediaItemSequence(audioItems),
                ),
            ).setEffects(Effects(audioProcessors, emptyList())).build()

            val encoders = DefaultEncoderFactory.Builder(context)
                .setRequestedVideoEncoderSettings(
                    VideoEncoderSettings.Builder().setBitrate(plan.bitrate).build(),
                )
                .setEnableFallback(true)
                .build()
            val t = Transformer.Builder(context)
                .setLooper(Looper.getMainLooper())
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setEncoderFactory(encoders)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        Log.i(TAG, "done ${exportResult.durationMs} ms, ${exportResult.fileSizeBytes} bytes")
                        finish(path = plan.output, durationMs = exportResult.durationMs)
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException,
                    ) {
                        Log.w(TAG, "export failed", exportException)
                        finish(error = "${exportException.errorCodeName}: ${exportException.message}")
                    }
                })
                .build()
            transformer = t
            File(plan.output).delete()
            t.start(composition, plan.output)
        } catch (e: Exception) {
            Log.w(TAG, "start failed", e)
            finish(error = "start: ${e.message}")
        }
    }

    private fun finish(path: String? = null, durationMs: Long = 0, error: String? = null) {
        val r = pending ?: return
        pending = null
        transformer = null
        overlay = null
        if (error != null) {
            r.error("render_failed", error, null)
        } else {
            r.success(mapOf("path" to path, "durationMs" to durationMs))
        }
    }

    /** Length of a whole file in ms (local path or http URL). */
    private fun durationMs(uri: String): Long {
        val r = MediaMetadataRetriever()
        try {
            if (uri.startsWith("http")) {
                r.setDataSource(uri, HashMap())
            } else {
                r.setDataSource(Uri.parse(uri).path)
            }
            return r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                ?: throw IllegalStateException("no duration for $uri")
        } finally {
            try {
                r.release()
            } catch (_: Exception) {
            }
        }
    }

    /** What Dart asked for, with every clip's length resolved. */
    private class Plan(
        val output: String,
        val fps: Int,
        val bitrate: Int,
        val backgroundUri: String,
        val backgroundIsImage: Boolean,
        val clips: List<Clip>,
        val silenceUri: String?,
        val overlays: List<TimedOverlay.Entry>,
        val totalUs: Long,
        val effect: Map<*, *>?,
    ) {
        class Clip(val uri: String, val startMs: Long?, val endMs: Long?)

        companion object {
            fun from(a: Map<*, *>, probe: (String) -> Long): Plan {
                val segments = a["segments"] as? List<*> ?: throw IllegalArgumentException("no segments")
                val clips = ArrayList<Clip>()
                val overlays = ArrayList<TimedOverlay.Entry>()
                var atUs = 0L
                for (s in segments) {
                    val seg = s as Map<*, *>
                    val startUs = atUs
                    for (c in seg["clips"] as List<*>) {
                        val m = c as Map<*, *>
                        val uri = m["uri"] as String
                        val start = (m["startMs"] as? Number)?.toLong()
                        val end = (m["endMs"] as? Number)?.toLong()
                        val lengthMs = if (end != null) {
                            end - (start ?: 0L)
                        } else {
                            probe(uri) - (start ?: 0L)
                        }
                        if (lengthMs <= 0) continue
                        clips += Clip(uri, start, end)
                        atUs += lengthMs * 1000
                    }
                    if (atUs > startUs) overlays += TimedOverlay.Entry(startUs, seg["overlay"] as String)
                }
                if (clips.isEmpty()) throw IllegalArgumentException("no audio")
                val closing = a["closing"] as? Map<*, *>
                var silenceUri: String? = null
                var totalUs = atUs
                if (closing != null) {
                    silenceUri = closing["silence"] as String
                    overlays += TimedOverlay.Entry(atUs, closing["overlay"] as String)
                    totalUs += ((closing["ms"] as Number).toLong()) * 1000
                }
                val bg = a["background"] as Map<*, *>
                return Plan(
                    output = a["output"] as String,
                    fps = (a["fps"] as? Number)?.toInt() ?: 30,
                    bitrate = (a["bitrate"] as? Number)?.toInt() ?: 5_000_000,
                    backgroundUri = bg["uri"] as String,
                    backgroundIsImage = bg["image"] == true,
                    clips = clips,
                    silenceUri = silenceUri,
                    overlays = overlays,
                    totalUs = totalUs,
                    effect = a["effect"] as? Map<*, *>,
                )
            }
        }
    }

    /**
     * One full-frame picture per stretch of time. Decoded unpremultiplied:
     * the overlay shader multiplies by alpha itself, so a premultiplied
     * bitmap would leave dark rims around the white letters.
     */
    private class TimedOverlay(private val entries: List<Entry>) : BitmapOverlay() {
        class Entry(val startUs: Long, val path: String)

        @Volatile
        var lastPtsUs = 0L
        private var index = -1
        private var current: Bitmap? = null

        override fun getBitmap(presentationTimeUs: Long): Bitmap {
            lastPtsUs = presentationTimeUs
            var i = entries.indexOfLast { presentationTimeUs >= it.startUs }
            if (i < 0) i = 0
            val now = current
            if (i != index || now == null) {
                index = i
                val opts = BitmapFactory.Options().apply {
                    inPremultiplied = false
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                }
                current = BitmapFactory.decodeFile(entries[i].path, opts)
                    ?: throw IllegalStateException("cannot read ${entries[i].path}")
            }
            return current!!
        }
    }

    companion object {
        const val CHANNEL = "com.mahfodqr.qalon_mushaf/ayah_video"
        private const val TAG = "AyahVideo"

        // A still background is one picture shown for this long, looped.
        private const val IMAGE_LOOP_US = 10_000_000L
        private const val OUTPUT_RATE = 44100
    }
}
