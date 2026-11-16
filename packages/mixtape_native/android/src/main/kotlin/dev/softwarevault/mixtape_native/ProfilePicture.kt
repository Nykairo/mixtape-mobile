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
 * A picture from the phone as a profile picture, made the way the computer makes one
 * (profiles.encode_picture there): its middle square, 256 pixels, turned the way the camera was held,
 * on label paper where it's see-through, as a JPEG in base64 of at most 150,000 characters.
 */
internal object ProfilePicture {
    private const val SIDE = 256

    fun from(context: Context, uri: Uri): String? {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        val w = bounds.outWidth
        val h = bounds.outHeight
        if (w < 32 || h < 32) return null
        // read at about twice the size it ends up: sharp, and quick even for a 50 megapixel photo
        var sample = 1
        while (min(w, h) / (sample * 2) >= SIDE * 2) sample *= 2
        val raw = resolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
        } ?: return null
        val turned = turn(raw, resolver.openInputStream(uri)?.use { exifTurn(it) } ?: 0)
        val s = min(turned.width, turned.height)
        val square = Rect((turned.width - s) / 2, (turned.height - s) / 2, (turned.width + s) / 2, (turned.height + s) / 2)
        val out = Bitmap.createBitmap(SIDE, SIDE, Bitmap.Config.ARGB_8888)
        Canvas(out).apply {
            drawColor(0xFFF1E6CF.toInt())
            drawBitmap(turned, square, Rect(0, 0, SIDE, SIDE), Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
        }
        if (turned !== raw) turned.recycle()
        raw.recycle()
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
