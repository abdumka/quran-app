package com.mahfodqr.qalon_mushaf

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException

/**
 * Serves the reciter name tiles (assets/reciter_art/<id>.png) to Android Auto
 * and to the media notification as content:// URIs, which is the only kind of
 * picture another process (the car's projection) can read from this app.
 *
 * content://com.mahfodqr.qalon_mushaf.reciterart/reciter/<id>.png
 *
 * Read-only. It hands out the bundled tiles and the ones the app itself
 * downloaded into files/reciter_art/ (QuranMediaHandler, from the public
 * quran-content bucket's reciter_art/ folder; tools/make_reciter_tiles.py).
 *
 * The tile is copied to the cache once per app install/update: a file inside
 * the APK cannot be opened as a whole-file descriptor, which is what the
 * readers ask for.
 */
class ReciterArtProvider : ContentProvider() {
    override fun onCreate(): Boolean {
        // Providers start with the process, before any service: the earliest
        // place to arm the car's «السور» list title (see QueueTitle).
        com.ryanheise.audioservice.QueueTitle.install()
        return true
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        if (mode != "r") throw SecurityException("read-only")
        val ctx = context ?: throw FileNotFoundException("no context")
        val name = uri.lastPathSegment ?: throw FileNotFoundException("no name")
        if (!NAME.matches(name)) throw FileNotFoundException(name)
        // A tile fetched from the server (for a reciter added after this
        // build) wins; then the reciter's own bundled tile; then its family's
        // (husary_timed -> husary_qaloun); then the generic one.
        val downloaded = File(File(ctx.filesDir, ASSET_DIR), name)
        if (downloaded.isFile && downloaded.length() > 0L) {
            return ParcelFileDescriptor.open(downloaded, ParcelFileDescriptor.MODE_READ_ONLY)
        }
        val bundled = ctx.assets.list(ASSET_DIR)?.toSet() ?: emptySet()
        val family = name.substringBefore('_') + "_qaloun.png"
        val source = when {
            name in bundled -> name
            family in bundled -> family
            else -> GENERIC
        }
        val stamp = try {
            ctx.packageManager.getPackageInfo(ctx.packageName, 0).lastUpdateTime
        } catch (e: Exception) {
            0L
        }
        val dir = File(ctx.cacheDir, "reciter_art_$stamp").apply { mkdirs() }
        val out = File(dir, source)
        synchronized(this) {
            if (!out.exists() || out.length() == 0L) {
                val tmp = File(dir, "$source.tmp")
                ctx.assets.open("$ASSET_DIR/$source").use { input ->
                    tmp.outputStream().use { input.copyTo(it) }
                }
                tmp.renameTo(out)
            }
        }
        return ParcelFileDescriptor.open(out, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String = "image/png"

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    private companion object {
        const val ASSET_DIR = "reciter_art"
        const val GENERIC = "generic.png"
        val NAME = Regex("[a-z0-9_]+\\.png")
    }
}
