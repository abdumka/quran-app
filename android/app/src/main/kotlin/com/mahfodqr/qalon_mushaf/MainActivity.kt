package com.mahfodqr.qalon_mushaf

import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.core.view.WindowCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Extends AudioServiceActivity (a FlutterActivity subclass) so just_audio_background
// / audio_service can attach its media session to this Activity's FlutterEngine.
class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Draw the Flutter surface edge-to-edge (behind the status and
        // navigation bars). Without this the decor view reserves space for the
        // status bar, so when full-screen mode hides the bar a black strip is
        // left in its place.
        WindowCompat.setDecorFitsSystemWindows(window, false)

        // Allow the content to render into the display cutout / status-bar area.
        // On real devices the status bar sits in the cutout region, which the
        // system otherwise letterboxes with a black bar once the bar is hidden
        // in full-screen mode. SHORT_EDGES lets the page fill that region too.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }

        // Android TV: hold the screen on from the very first frame.
        //
        // Dart asks for this too (wakelock_plus sets exactly this flag), but
        // only once the engine is up and the reader has built, and it swallows
        // the NoActivityException it throws if the plugin has not been attached
        // to an Activity yet. A television left playing a long tilawah with no
        // remote input went to standby after about fifteen minutes, so the flag
        // needs to be on before any of that can go wrong. A TV has no battery
        // to protect, and the app being in the foreground means someone is
        // using it.
        if (isAndroidTv()) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    // Tells Dart whether this is an Android TV. Nothing on the Flutter side can
    // answer that: a 1080p TV reports 960x540 logical pixels at density 320, so
    // MediaQuery heuristics (shortestSide >= 600) classify it as a phone and the
    // reader then picks its phone-landscape layout. PackageManager is the only
    // reliable signal.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLATFORM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAndroidTv" -> result.success(isAndroidTv())
                    else -> result.notImplemented()
                }
            }
    }

    private fun isAndroidTv(): Boolean {
        // Leanback is the canonical marker; TELEVISION is checked too because a
        // few older/odd boxes report only one of the pair.
        return packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_TELEVISION)
    }

    companion object {
        private const val PLATFORM_CHANNEL = "com.mahfodqr.qalon_mushaf/platform"
    }
}
