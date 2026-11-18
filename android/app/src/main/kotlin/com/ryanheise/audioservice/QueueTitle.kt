package com.ryanheise.audioservice

import android.os.Looper
import android.support.v4.media.session.MediaSessionCompat
import android.util.Log
import java.lang.ref.WeakReference

/**
 * Gives the media session's queue a title, which Android Auto shows on the
 * player's list button and over the list («السور» instead of "Queue").
 *
 * audio_service keeps the queue title on the Dart side and never hands it to
 * Android, so it is set here on the session itself. This file sits in
 * audio_service's package only to read its package-private
 * [AudioService.instance]; the session field is private and is found by type.
 *
 * The service can start with no screen (the car connecting with the app
 * closed), so nothing in an Activity can do this. [install] runs at process
 * start (ReciterArtProvider.onCreate) and watches the main thread's idle
 * moments: one static read each, and the title is set once per service.
 */
object QueueTitle {
    private const val TITLE = "السور"
    private var titled = WeakReference<AudioService>(null)

    /** Call on the main thread. */
    fun install() {
        Looper.myQueue().addIdleHandler {
            val service = AudioService.instance
            if (service != null && service !== titled.get()) {
                if (apply(service)) titled = WeakReference(service)
            }
            true // keep watching: a later service needs its title too
        }
    }

    private fun apply(service: AudioService): Boolean = try {
        val field = AudioService::class.java.declaredFields
            .firstOrNull { it.type == MediaSessionCompat::class.java }
        if (field == null) {
            titled = WeakReference(service) // nothing to do; don't retry
            false
        } else {
            field.isAccessible = true
            val session = field.get(service) as MediaSessionCompat?
            session?.setQueueTitle(TITLE)
            session != null
        }
    } catch (e: Exception) {
        Log.w("QueueTitle", "queue title not set", e)
        titled = WeakReference(service)
        false
    }
}
