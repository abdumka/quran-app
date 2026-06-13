package com.mahfodqr.qalon_mushaf

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
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
    }
}
