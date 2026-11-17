package dev.softwarevault.mixtape_native

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import java.io.File
import java.security.MessageDigest

/**
 * Music files on the phone itself: opened with Mixtape from a files app ("Open with", or shared to it),
 * or picked in Add music. They play from where they are. What's written inside each one (title,
 * artist, album, length and its cover) is read here, the way the computer reads a music folder.
 */
internal object PhoneMusic {
    private const val MOST = 300 // a whole album or ten, not a whole phone
    private const val COVER = 544

    /** The music files an intent brings: one opened with Mixtape, or one or more shared to it. */
    fun urisOf(intent: Intent?): List<Uri> {
        if (intent == null || intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return emptyList()
        val found = when (intent.action) {
            Intent.ACTION_VIEW -> listOfNotNull(intent.data)
            Intent.ACTION_SEND -> listOfNotNull(stream(intent))
            Intent.ACTION_SEND_MULTIPLE -> streams(intent)
            else -> return emptyList()
        }
        // taken: the app coming back later doesn't open them again
        intent.action = Intent.ACTION_MAIN
        intent.data = null
        intent.removeExtra(Intent.EXTRA_STREAM)
        return found.filter { it.scheme == "content" }.take(MOST)
    }

    /** The files picked in the phone's own file picker (one, or several). */
    fun picked(data: Intent?): List<Uri> {
        val clip: ClipData? = data?.clipData
        val uris = if (clip != null) (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri } else listOfNotNull(data?.data)
        return uris.filter { it.scheme == "content" }.take(MOST)
    }

    /** Songs the way the app keeps them ("file" songs), in the order they came. */
    fun read(context: Context, uris: List<Uri>): List<Map<String, Any>> = uris.map { read(context, it) }

    private fun read(context: Context, uri: Uri): Map<String, Any> {
        val name = nameOf(context, uri)
        val song = mutableMapOf<String, Any>("src" to "file", "ref" to uri.toString(), "title" to name)
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(context, uri)
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)?.trim()?.takeIf { it.isNotEmpty() }?.let { song["title"] = it }
            (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST) ?: r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST))
                ?.trim()?.takeIf { it.isNotEmpty() }?.let { song["artist"] = it }
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)?.trim()?.takeIf { it.isNotEmpty() }?.let { song["album"] = it }
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()?.let { song["dur"] = (it / 1000).toInt() }
            val art = cover(context, uri, r.embeddedPicture)
            if (art.isNotEmpty()) song["art"] = art
        } catch (e: RuntimeException) {
            // nothing written inside it that the phone can read: it goes by its file name, and the
            // player still gets its turn at it
        } finally {
            try {
                r.release()
            } catch (e: Exception) {
                // already let go
            }
        }
        return song
    }

    /** The file's name without its ending ("Track 01.mp3" is "Track 01"). */
    private fun nameOf(context: Context, uri: Uri): String {
        val shown = try {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst() && !c.isNull(0)) c.getString(0) else null
            }
        } catch (e: RuntimeException) {
            null
        } ?: uri.lastPathSegment.orEmpty()
        val bare = shown.substringAfterLast('/')
        return (if (bare.contains('.')) bare.substringBeforeLast('.') else bare).replace('_', ' ').trim().ifEmpty { "Untitled" }
    }

    /** The cover inside the file as a small JPEG in the cache: its path, or "" when it has none. */
    private fun cover(context: Context, uri: Uri, bytes: ByteArray?): String {
        if (bytes == null || bytes.isEmpty()) return ""
        val folder = File(context.cacheDir, "phone-covers").apply { mkdirs() }
        val file = File(folder, "${key(uri.toString())}.jpg")
        if (file.isFile) return file.path
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return ""
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= COVER) sample *= 2
        val image = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: return ""
        try {
            val tmp = File(folder, "${file.name}.tmp")
            tmp.outputStream().use { image.compress(Bitmap.CompressFormat.JPEG, 86, it) }
            if (!tmp.renameTo(file)) tmp.delete()
        } catch (e: java.io.IOException) {
            return "" // a full phone: no cover this time
        } finally {
            image.recycle()
        }
        tidy(folder)
        return if (file.isFile) file.path else ""
    }

    /** The covers folder keeps the newest few hundred. */
    private fun tidy(folder: File) {
        val all = folder.listFiles() ?: return
        if (all.size <= 400) return
        all.sortedBy { it.lastModified() }.take(all.size - 300).forEach { it.delete() }
    }

    private fun key(text: String): String =
        MessageDigest.getInstance("SHA-1").digest(text.toByteArray()).joinToString("") { "%02x".format(it) }.take(20)

    private fun stream(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }

    private fun streams(intent: Intent): List<Uri> =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty()
        }
}
