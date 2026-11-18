package com.mahfodqr.qalon_mushaf

import android.content.Context
import android.net.Uri
import android.view.LayoutInflater
import android.view.View
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File

/**
 * Plays a finished «فيديو الآية» inside the share sheet.
 *
 * Built on the same Media3 1.4.1 ExoPlayer that just_audio already ships, so
 * no second player library comes in (the video_player plugin would pull Media3
 * 1.9 and drag the recitation player and the Transformer along with it).
 *
 * Creation params: {"path": "/abs/file.mp4"}. It starts playing at once, plays
 * one time and stops on the last frame. Flutter draws the controls and talks to
 * it on "<VIEW_TYPE>_<viewId>": play, pause, state.
 */
@OptIn(UnstableApi::class)
class AyahVideoPlayerFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val path = (args as? Map<*, *>)?.get("path") as? String ?: ""
        return AyahVideoPlayerView(context, messenger, viewId, path)
    }

    companion object {
        const val VIEW_TYPE = "com.mahfodqr.qalon_mushaf/ayah_video_player"
    }
}

@OptIn(UnstableApi::class)
private class AyahVideoPlayerView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    path: String,
) : PlatformView, MethodChannel.MethodCallHandler {

    // Takes audio focus like any video: a recitation playing in the
    // background pauses instead of talking over the preview.
    private val player: ExoPlayer = ExoPlayer.Builder(context).build().apply {
        setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build(),
            true,
        )
        repeatMode = Player.REPEAT_MODE_OFF
        if (path.isNotEmpty()) setMediaItem(MediaItem.fromUri(Uri.fromFile(File(path))))
        playWhenReady = true
        prepare()
    }

    private val playerView: PlayerView =
        (LayoutInflater.from(context).inflate(R.layout.ayah_video_player, null) as PlayerView)
            .also { it.player = player }

    private val channel = MethodChannel(messenger, "${AyahVideoPlayerFactory.VIEW_TYPE}_$viewId")
        .also { it.setMethodCallHandler(this) }

    override fun getView(): View = playerView

    override fun dispose() {
        channel.setMethodCallHandler(null)
        playerView.player = null
        player.release()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "play" -> {
                if (player.playbackState == Player.STATE_ENDED) player.seekTo(0)
                player.play()
                result.success(null)
            }
            "pause" -> {
                player.pause()
                result.success(null)
            }
            "state" -> {
                val duration = player.duration
                result.success(
                    mapOf(
                        "position" to player.currentPosition,
                        "duration" to if (duration == C.TIME_UNSET) 0L else duration,
                        // "Meant to play", so the play button does not
                        // flash while the first frames load.
                        "playing" to (player.playWhenReady &&
                            player.playbackState != Player.STATE_ENDED),
                        "ended" to (player.playbackState == Player.STATE_ENDED),
                        "error" to (player.playerError != null),
                    ),
                )
            }
            else -> result.notImplemented()
        }
    }
}
