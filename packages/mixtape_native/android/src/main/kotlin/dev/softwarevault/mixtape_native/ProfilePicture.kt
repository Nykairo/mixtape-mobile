package dev.softwarevault.mixtape_native

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.media.ExifInterface
import android.net.Uri
import android.util.Base64
import java.io.ByteArrayOutputStream
import kotlin.math.min

/**
 * Pictures picked on the phone, made the way the computer makes them: a profile picture
 * (profiles.encode_picture there) is the middle square, 256 pixels, on label paper where it's
 * see-through, a JPEG in base64 of at most 150,000 characters; a photo for a tape
 * (decor.import_picture there) is at most 640 pixels long, a PNG when it really has see-through
 * parts, else a JPEG. Both are turned the way the camera was held.
 */
internal object ProfilePicture {
    private const val SIDE = 256
    private const val TAPE = 640

    /** A photo for a tape: {"data": base64, "png": whether it's a PNG}. */
    fun forTape(context: Context, uri: Uri): Map<String, Any>? {
        val raw = read(context, uri, TAPE) ?: return null
        val k = min(1f, TAPE.toFloat() / maxOf(raw.width, raw.height))
        val sized = if (k < 1f) Bitmap.createScaledBitmap(raw, (raw.width * k).toInt().coerceAtLeast(1), (raw.height * k).toInt().coerceAtLeast(1), true) else raw
        if (sized !== raw) raw.recycle()
        try {
            val png = sized.hasAlpha() && hasHoles(sized)
            val bytes = ByteArrayOutputStream().also {
                sized.compress(if (png) Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG, 88, it)
            }.toByteArray()
            if (bytes.size > 2_000_000) return null
            return mapOf("data" to Base64.encodeToString(bytes, Base64.NO_WRAP), "png" to png)
        } finally {
            sized.recycle()
        }
    }

    /** Does the picture really use see-through parts? A grid of points, not every pixel. */
    private fun hasHoles(b: Bitmap): Boolean {
        val stepX = maxOf(1, b.width / 24)
        val stepY = maxOf(1, b.height / 24)
        for (y in 0 until b.height step stepY) {
            for (x in 0 until b.width step stepX) {
                if ((b.getPixel(x, y) ushr 24) < 250) return true
            }
        }
        return false
    }

    /** The picture read at about twice [side] on its short side, turned upright; null when it isn't one. */
    private fun read(context: Context, uri: Uri, side: Int): Bitmap? {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        val w = bounds.outWidth
        val h = bounds.outHeight
        if (w < 32 || h < 32) return null
        var sample = 1
        while (min(w, h) / (sample * 2) >= side * 2) sample *= 2
        val raw = resolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
        } ?: return null
        val turned = turn(raw, resolver.openInputStream(uri)?.use { exifTurn(it) } ?: 0)
        if (turned !== raw) raw.recycle()
        return turned
    }

    fun from(context: Context, uri: Uri): String? {
        // read at about twice the size it ends up: sharp, and quick even for a 50 megapixel photo
        val turned = read(context, uri, SIDE) ?: return null
        val s = min(turned.width, turned.height)
        val square = Rect((turned.width - s) / 2, (turned.height - s) / 2, (turned.width + s) / 2, (turned.height + s) / 2)
        val out = Bitmap.createBitmap(SIDE, SIDE, Bitmap.Config.ARGB_8888)
        Canvas(out).apply {
            drawColor(0xFFF1E6CF.toInt())
            drawBitmap(turned, square, Rect(0, 0, SIDE, SIDE), Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
        }
        turned.recycle()
        try {
            for (quality in intArrayOf(86, 72, 58)) {
                val bytes = ByteArrayOutputStream().also { out.compress(Bitmap.CompressFormat.JPEG, quality, it) }.toByteArray()
                val data = Base64.encodeToString(bytes, Base64.NO_WRAP)
                if (data.length <= 150_000) return data
            }
            return null
        } finally {
            out.recycle()
        }
    }

    /** How far a photo has to turn to stand the way it was taken, from its EXIF. */
    private fun exifTurn(stream: java.io.InputStream): Int = when (
        ExifInterface(stream).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
    ) {
        ExifInterface.ORIENTATION_ROTATE_90 -> 90
        ExifInterface.ORIENTATION_ROTATE_180 -> 180
        ExifInterface.ORIENTATION_ROTATE_270 -> 270
        else -> 0
    }

    private fun turn(b: Bitmap, degrees: Int): Bitmap =
        if (degrees == 0) b else Bitmap.createBitmap(b, 0, 0, b.width, b.height, Matrix().apply { postRotate(degrees.toFloat()) }, true)
}
