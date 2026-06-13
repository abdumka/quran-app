package com.mahfodqr.qalon_mushaf

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Draw the Flutter surface edge-to-edge (behind the status and
        // navigation bars). Without this the decor view reserves space for the
        // status bar, so when full-screen mode hides the bar a black strip is
        // left in its place. This guarantees the content fills the whole
        // screen from the very first frame, even when the app cold-starts
        // directly into full-screen mode.
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }
}
