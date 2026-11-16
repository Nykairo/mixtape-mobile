package dev.softwarevault.mixtape_native

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import java.io.File
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * The pictures on the widgets, drawn here because a widget can only show views the launcher knows:
 * the cassette with the song on its label, the little tapes on the shelf, the cover with round
 * corners, and the cover blurred and darkened behind the Now playing card.
 */
internal object WidgetArt {
    private const val ORANGE = 0xFFFF6A1A.toInt()
    private const val CREAM = 0xFFF6ECD8.toInt()
    private const val DECK = 0xFF191410.toInt()

    /** The handwriting the app writes on its labels; the tests set it from the font file itself. */
    @Volatile
    var hand: Typeface? = null

    fun handwriting(context: Context): Typeface {
        hand?.let { return it }
        val face = try {
            Typeface.createFromAsset(context.assets, "flutter_assets/assets/fonts/CoveredByYourGrace.ttf")
        } catch (e: Exception) {
            Typeface.create("casual", Typeface.NORMAL)
        }
        hand = face
        return face
    }

    // ------------------------------------------------------------------ covers

    /** The cover file, read at about [size] pixels (never the whole big picture). */
    fun cover(path: String, size: Int): Bitmap? {
        if (path.isEmpty() || !File(path).isFile) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0) return null
        var sample = 1
        while (min(bounds.outWidth, bounds.outHeight) / (sample * 2) >= size) sample *= 2
        return BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
    }

    /** The middle square of [src], [size] pixels, with round corners; a dark square with a note when there's none. */
    fun rounded(src: Bitmap?, size: Int, radius: Float): Bitmap {
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val p = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        val box = RectF(0f, 0f, size.toFloat(), size.toFloat())
        if (src == null) {
            p.shader = LinearGradient(0f, 0f, size.toFloat(), size.toFloat(), 0xFF3A2E26.toInt(), 0xFF221A15.toInt(), Shader.TileMode.CLAMP)
            c.drawRoundRect(box, radius, radius, p)
            p.shader = null
            note(c, size / 2f, size / 2f, size * 0.42f, 0x66F6ECD8)
            return out
        }
        p.shader = BitmapShader(src, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply { setLocalMatrix(fill(src, size.toFloat(), size.toFloat())) }
        c.drawRoundRect(box, radius, radius, p)
        return out
    }

    /** Paints with [s] from now on, fully: a paint dims its shader by the alpha of the last color it had. */
    private fun Paint.shade(s: Shader) {
        color = Color.BLACK
        shader = s
    }

    /** A matrix that scales [src] to cover [w]×[h], centered. */
    private fun fill(src: Bitmap, w: Float, h: Float, x: Float = 0f, y: Float = 0f): Matrix {
        val scale = max(w / src.width, h / src.height)
        return Matrix().apply {
            setScale(scale, scale)
            postTranslate(x + (w - src.width * scale) / 2f, y + (h - src.height * scale) / 2f)
        }
    }

    /** A music note, for when there's no cover. */
    private fun note(c: Canvas, cx: Float, cy: Float, size: Float, color: Int) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        val r = size * 0.18f
        c.drawOval(RectF(cx - size * 0.32f - r, cy + size * 0.22f - r * 0.8f, cx - size * 0.32f + r, cy + size * 0.22f + r * 0.8f), p)
        c.drawOval(RectF(cx + size * 0.18f - r, cy + size * 0.12f - r * 0.8f, cx + size * 0.18f + r, cy + size * 0.12f + r * 0.8f), p)
        p.strokeWidth = size * 0.07f
        p.style = Paint.Style.STROKE
        c.drawLine(cx - size * 0.32f + r * 0.9f, cy + size * 0.22f, cx - size * 0.32f + r * 0.9f, cy - size * 0.38f, p)
        c.drawLine(cx + size * 0.18f + r * 0.9f, cy + size * 0.12f, cx + size * 0.18f + r * 0.9f, cy - size * 0.48f, p)
        p.style = Paint.Style.FILL
        val beam = Path().apply {
            moveTo(cx - size * 0.32f + r * 0.9f - size * 0.035f, cy - size * 0.38f)
            lineTo(cx + size * 0.18f + r * 0.9f + size * 0.035f, cy - size * 0.48f)
            lineTo(cx + size * 0.18f + r * 0.9f + size * 0.035f, cy - size * 0.34f)
            lineTo(cx - size * 0.32f + r * 0.9f - size * 0.035f, cy - size * 0.24f)
            close()
        }
        c.drawPath(beam, p)
    }

    /**
     * The cover, blurred and darkened, as the background of a card [w]×[h]: shrunk to a few dozen pixels
     * and drawn big again, which blurs it for next to nothing. Without a cover, the deck's warm black
     * with a little orange glow. Small, for the launcher to stretch; with a [radius] (only needed before
     * Android 12, where nothing clips a widget's corners) it comes in the card's full size with them cut.
     */
    fun backdrop(src: Bitmap?, w: Int, h: Int, radius: Float = 0f): Bitmap {
        val small = max(16, min(w, h) / 10)
        val bw = max(small, small * w / max(1, h))
        val out = Bitmap.createBitmap(bw * 4, small * 4, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val p = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        val ow = out.width.toFloat()
        val oh = out.height.toFloat()
        if (src != null) {
            val tiny = Bitmap.createBitmap(bw, small, Bitmap.Config.ARGB_8888)
            Canvas(tiny).drawBitmap(src, fill(src, bw.toFloat(), small.toFloat()), Paint(Paint.FILTER_BITMAP_FLAG))
            val blur = Bitmap.createScaledBitmap(tiny, bw / 2 + 1, small / 2 + 1, true)
            c.drawBitmap(blur, null, RectF(-ow * 0.05f, -oh * 0.05f, ow * 1.05f, oh * 1.05f), p)
            p.shader = LinearGradient(0f, 0f, ow, 0f, 0x8C140A12.toInt(), 0xCC140A12.toInt(), Shader.TileMode.CLAMP)
            c.drawRect(0f, 0f, ow, oh, p)
        } else {
            p.shader = LinearGradient(0f, 0f, 0f, oh, 0xFF2B211B.toInt(), 0xFF161210.toInt(), Shader.TileMode.CLAMP)
            c.drawRect(0f, 0f, ow, oh, p)
            p.shader = RadialGradient(ow * 0.15f, oh * 0.1f, ow * 0.6f, 0x40FF6A1A, 0x00FF6A1A, Shader.TileMode.CLAMP)
            c.drawRect(0f, 0f, ow, oh, p)
        }
        if (radius <= 0f) return out
        val full = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val stretched = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        stretched.shader = BitmapShader(out, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply {
            setLocalMatrix(Matrix().apply { setScale(w / ow, h / oh) })
        }
        Canvas(full).drawRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), radius, radius, stretched)
        out.recycle()
        return full
    }

    /**
     * The Cover widget's picture, [w]×[h]: the cover filling it, darker toward the bottom where the song
     * is written over it, with round corners when [radius] says so. Without a cover, the deck's warm
     * black with a note.
     */
    fun coverCard(src: Bitmap?, w: Int, h: Int, radius: Float): Bitmap {
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val p = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        val box = RectF(0f, 0f, w.toFloat(), h.toFloat())
        if (src != null) {
            p.shade(BitmapShader(src, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply { setLocalMatrix(fill(src, box.width(), box.height())) })
        } else {
            p.shade(LinearGradient(0f, 0f, box.width(), box.height(), 0xFF3A2E26.toInt(), 0xFF1B1511.toInt(), Shader.TileMode.CLAMP))
        }
        c.drawRoundRect(box, radius, radius, p)
        if (src == null) note(c, w / 2f, h * 0.42f, min(w, h) * 0.4f, 0x4DF6ECD8)
        // the shade for the words: nothing over the top half, then darker and darker
        p.shader = LinearGradient(0f, h * 0.42f, 0f, h.toFloat(), intArrayOf(0x00100A08, 0x59100A08, 0xE0100A08.toInt()),
            floatArrayOf(0f, 0.45f, 1f), Shader.TileMode.CLAMP)
        c.drawRoundRect(box, radius, radius, p)
        return out
    }

    // ------------------------------------------------------------------ the cassette

    private fun mix(a: Int, b: Int, t: Float): Int {
        fun ch(x: Int, y: Int) = (x + (y - x) * t).roundToInt().coerceIn(0, 255)
        return Color.argb(ch(Color.alpha(a), Color.alpha(b)), ch(Color.red(a), Color.red(b)),
            ch(Color.green(a), Color.green(b)), ch(Color.blue(a), Color.blue(b)))
    }

    private fun light(c: Int) = (0.299 * Color.red(c) + 0.587 * Color.green(c) + 0.114 * Color.blue(c)) > 150

    /** Where the cassette widget's three keys are, in the picture: the song before, play or pause, the next one. */
    class Keys(val area: RectF)

    /**
     * The cassette widget's picture, [w]×[h] pixels: the cassette as big as fits, in the colors of the
     * tape that plays, with the cover glued onto the label like a photo, the song written on it by
     * hand, the reels wound as far as the music is into the tape, and the keys in its head.
     */
    fun cassette(context: Context, s: Playing?, w: Int, h: Int, density: Float): Pair<Bitmap, Keys> {
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val margin = 4f * density
        val cw = min(w - 2 * margin, (h - 2 * margin) * 1.574f)
        val ch = cw / 1.574f
        val x0 = (w - cw) / 2f
        val y0 = (h - ch) / 2f
        val look = s?.colors ?: TapeColors.PLAIN
        val p = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        val shell = RectF(x0, y0, x0 + cw, y0 + ch)
        val corner = cw * 0.05f

        // a soft shadow under it, then the shell, lighter at the top
        p.color = 0x73000000
        p.maskFilter = BlurMaskFilter(max(1f, cw * 0.025f), BlurMaskFilter.Blur.NORMAL)
        c.drawRoundRect(RectF(shell.left + cw * 0.01f, shell.top + ch * 0.05f, shell.right - cw * 0.01f, shell.bottom + ch * 0.025f), corner, corner, p)
        p.maskFilter = null
        val shellTop = mix(look.shell, Color.WHITE, 0.12f)
        val shellLow = mix(look.shell, Color.BLACK, 0.18f)
        val alpha = look.shellAlpha.coerceIn(150, 255)
        p.shade(LinearGradient(0f, shell.top, 0f, shell.bottom,
            (shellTop and 0x00FFFFFF) or (alpha shl 24), (shellLow and 0x00FFFFFF) or (alpha shl 24), Shader.TileMode.CLAMP))
        c.drawRoundRect(shell, corner, corner, p)
        p.shader = null
        p.style = Paint.Style.STROKE
        p.strokeWidth = max(1f, cw * 0.006f)
        p.color = 0x24FFFFFF
        c.drawRoundRect(RectF(shell.left + p.strokeWidth, shell.top + p.strokeWidth, shell.right - p.strokeWidth, shell.bottom - p.strokeWidth), corner, corner, p)
        p.style = Paint.Style.FILL

        // the label, its stripes, the side, and the window with the reels
        val label = RectF(x0 + cw * 0.06f, y0 + ch * 0.075f, x0 + cw * 0.94f, y0 + ch * 0.705f)
        val lh = label.height()
        p.shade(LinearGradient(0f, label.top, 0f, label.bottom, mix(look.paper, Color.WHITE, 0.08f), mix(look.paper, Color.BLACK, 0.06f), Shader.TileMode.CLAMP))
        c.drawRoundRect(label, cw * 0.016f, cw * 0.016f, p)
        p.shader = null
        stripes(c, p, look, RectF(label.left, label.top + lh * 0.40f, label.right, label.top + lh * 0.585f))
        val wcy = label.top + lh * 0.735f
        val window = RectF(x0 + cw * 0.23f, wcy - ch * 0.1025f, x0 + cw * 0.77f, wcy + ch * 0.1025f)
        side(c, p, label, look)
        reels(c, p, window, look, s?.along ?: 0f)

        // the photo: the cover glued on the label's left end, a little crooked, with a strip of tape
        val photoSize = lh * 0.46f
        val px = label.left + cw * 0.075f + photoSize / 2f
        val py = label.top + lh * 0.075f + photoSize / 2f
        val photo = cover(s?.art ?: "", (photoSize * 1.2f).toInt())
        c.save()
        c.rotate(-4f, px, py)
        p.color = 0x38000000
        p.maskFilter = BlurMaskFilter(max(1f, photoSize * 0.04f), BlurMaskFilter.Blur.NORMAL)
        c.drawRect(px - photoSize / 2f + photoSize * 0.03f, py - photoSize / 2f + photoSize * 0.05f, px + photoSize / 2f + photoSize * 0.03f, py + photoSize / 2f + photoSize * 0.05f, p)
        p.maskFilter = null
        p.color = 0xFFFDFBF6.toInt()
        c.drawRect(px - photoSize / 2f, py - photoSize / 2f, px + photoSize / 2f, py + photoSize / 2f, p)
        val inset = photoSize * 0.07f
        val inner = RectF(px - photoSize / 2f + inset, py - photoSize / 2f + inset, px + photoSize / 2f - inset, py + photoSize / 2f - inset)
        if (photo != null) {
            p.shade(BitmapShader(photo, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply {
                setLocalMatrix(fill(photo, inner.width(), inner.height(), inner.left, inner.top))
            })
            c.drawRect(inner, p)
            p.shader = null
        } else {
            p.color = 0xFF2A211C.toInt()
            c.drawRect(inner, p)
            note(c, inner.centerX(), inner.centerY(), inner.width() * 0.7f, 0x99F6ECD8.toInt())
        }
        p.color = 0x8CFFF6D6.toInt()
        c.rotate(3f, px, py - photoSize / 2f)
        c.drawRect(px - photoSize * 0.2f, py - photoSize / 2f - photoSize * 0.07f, px + photoSize * 0.2f, py - photoSize / 2f + photoSize * 0.08f, p)
        c.restore()

        // the song, by hand, on the label's lines to the right of the photo
        val textLeft = px + photoSize / 2f + cw * 0.035f
        val textRight = label.right - cw * 0.035f
        val ink = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = look.ink; typeface = handwriting(context) }
        val title = s?.title?.ifEmpty { null } ?: "Mixtape"
        val artist = s?.artist?.ifEmpty { null } ?: if (s == null) "press play" else ""
        written(c, ink, title, textLeft, textRight, label.top + lh * 0.24f, lh * 0.2f)
        ink.alpha = 190
        written(c, ink, artist, textLeft, textRight, label.top + lh * 0.365f, lh * 0.125f)

        if (look.screws) screws(c, p, shell, look)

        // the head at the bottom, where the keys are
        val t0 = y0 + ch * 0.775f
        val head = Path().apply {
            moveTo(x0 + cw * 0.21f, t0)
            lineTo(x0 + cw * 0.79f, t0)
            lineTo(x0 + cw * 0.845f, shell.bottom - 0.5f)
            lineTo(x0 + cw * 0.155f, shell.bottom - 0.5f)
            close()
        }
        p.color = if (light(look.shell)) mix(look.shell, Color.BLACK, 0.1f) else mix(look.shell, Color.WHITE, 0.08f)
        c.drawPath(head, p)
        p.color = 0x1FFFFFFF
        c.drawRect(x0 + cw * 0.21f, t0, x0 + cw * 0.79f, t0 + max(1f, cw * 0.004f), p)
        val keys = RectF(x0 + cw * 0.21f, t0, x0 + cw * 0.79f, shell.bottom)
        keyGlyphs(c, keys, s?.playing == true, light(look.shell))
        return out to Keys(keys)
    }

    private fun stripes(c: Canvas, p: Paint, look: TapeColors, band: RectF) {
        val s = look.stripes
        when (look.stripeStyle) {
            "none" -> {}
            "band" -> {
                p.color = s[0]
                c.drawRect(band.left, band.top, band.right, band.top + band.height() * 0.62f, p)
            }
            "lines" -> {
                val line = band.height() * 0.12f
                for (k in 0 until 3) {
                    p.color = s[k % s.size]
                    val y = band.top + band.height() * (0.12f + k * 0.3f)
                    c.drawRect(band.left, y, band.right, y + line, p)
                }
            }
            "fade" -> {
                p.shade(LinearGradient(band.left, 0f, band.right, 0f, s[0], s[min(2, s.size - 1)], Shader.TileMode.CLAMP))
                c.drawRect(band.left, band.top, band.right, band.top + band.height() * 0.7f, p)
                p.shader = null
            }
            else -> {
                var top = band.top
                for ((k, f) in listOf(0.46f, 0.32f, 0.22f).withIndex()) {
                    p.color = s[k % s.size]
                    c.drawRect(band.left, top, band.right, top + band.height() * f + 0.5f, p)
                    top += band.height() * f
                }
            }
        }
    }

    /** The "A" box in the label's corner, like on a real tape. */
    private fun side(c: Canvas, p: Paint, label: RectF, look: TapeColors) {
        val size = label.height() * 0.13f
        val box = RectF(label.right - size * 1.6f, label.top + label.height() * 0.06f, label.right - size * 0.6f, label.top + label.height() * 0.06f + size)
        p.style = Paint.Style.STROKE
        p.strokeWidth = max(1f, size * 0.08f)
        p.color = mix(look.ink, look.paper, 0.35f)
        c.drawRect(box, p)
        p.style = Paint.Style.FILL
        p.textAlign = Paint.Align.CENTER
        p.textSize = size * 0.8f
        p.typeface = Typeface.DEFAULT_BOLD
        c.drawText("A", box.centerX(), box.bottom - size * 0.2f, p)
        p.textAlign = Paint.Align.LEFT
        p.typeface = null
    }

    private fun reels(c: Canvas, p: Paint, window: RectF, look: TapeColors, along: Float) {
        p.color = 0xFF0E0B09.toInt()
        c.drawRoundRect(window, window.height() * 0.5f, window.height() * 0.5f, p)
        c.save()
        val clip = Path().apply { addRoundRect(window, window.height() * 0.5f, window.height() * 0.5f, Path.Direction.CW) }
        c.clipPath(clip)
        val hubR = window.height() * 0.24f
        val smallest = hubR * 1.25f
        val biggest = window.height() * 1.05f
        val cy = window.centerY()
        for ((x, wound) in listOf(window.left + window.width() * 0.2f to 1f - along, window.right - window.width() * 0.2f to along)) {
            val r = smallest + (biggest - smallest) * wound
            p.shade(RadialGradient(x, cy, r, intArrayOf(mix(look.tape, Color.BLACK, 0.5f), look.tape, mix(look.tape, Color.WHITE, 0.08f), mix(look.tape, Color.BLACK, 0.4f)),
                floatArrayOf(0f, 0.55f, 0.92f, 1f), Shader.TileMode.CLAMP))
            c.drawCircle(x, cy, r, p)
            p.shader = null
            hub(c, p, x, cy, hubR, look.hub)
        }
        // the window's glass
        p.shade(LinearGradient(window.left, window.top, window.left + window.width() * 0.4f, window.bottom, 0x14FFFFFF, 0x00FFFFFF, Shader.TileMode.CLAMP))
        c.drawRect(window, p)
        p.shader = null
        c.restore()
    }

    private fun hub(c: Canvas, p: Paint, x: Float, y: Float, r: Float, color: Int) {
        p.color = color
        c.drawCircle(x, y, r, p)
        p.color = 0xFF120E0B.toInt()
        c.drawCircle(x, y, r * 0.62f, p)
        p.color = color
        for (k in 0 until 6) {
            val a = Math.toRadians(k * 60.0 + 15.0)
            c.save()
            c.translate(x + (cos(a) * r * 0.5f).toFloat(), y + (sin(a) * r * 0.5f).toFloat())
            c.rotate(k * 60f + 15f)
            c.drawRect(-r * 0.14f, -r * 0.1f, r * 0.14f, r * 0.1f, p)
            c.restore()
        }
    }

    private fun screws(c: Canvas, p: Paint, shell: RectF, look: TapeColors) {
        val r = shell.width() * 0.012f
        val spots = listOf(
            shell.left + shell.width() * 0.032f to shell.top + shell.height() * 0.055f,
            shell.right - shell.width() * 0.032f to shell.top + shell.height() * 0.055f,
            shell.left + shell.width() * 0.032f to shell.bottom - shell.height() * 0.07f,
            shell.right - shell.width() * 0.032f to shell.bottom - shell.height() * 0.07f,
        )
        for ((x, y) in spots) {
            p.color = look.screw
            c.drawCircle(x, y, r, p)
            p.color = 0x66000000
            p.strokeWidth = max(1f, r * 0.3f)
            c.drawLine(x - r * 0.6f, y - r * 0.6f, x + r * 0.6f, y + r * 0.6f, p)
        }
    }

    /** [text] written by hand from [left], shrunk until it fits up to [right] (and cut short with … if it still doesn't). */
    private fun written(c: Canvas, ink: Paint, text: String, left: Float, right: Float, baseline: Float, size: Float) {
        if (text.isEmpty()) return
        ink.textSize = size
        val room = right - left
        if (ink.measureText(text) > room) ink.textSize = max(size * 0.72f, size * room / ink.measureText(text))
        var shown = text
        if (ink.measureText(shown) > room) {
            while (shown.length > 1 && ink.measureText("$shown…") > room) shown = shown.dropLast(1)
            shown = shown.trimEnd() + "…"
        }
        c.drawText(shown, left, baseline, ink)
    }

    /** The song before, play or pause on an orange key, and the next one, spread over [area]. */
    private fun keyGlyphs(c: Canvas, area: RectF, playing: Boolean, lightShell: Boolean) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        val cy = area.centerY() + area.height() * 0.04f
        val r = area.height() * 0.36f
        val third = area.width() / 3f
        val glyph = if (lightShell) 0xFF2A211C.toInt() else CREAM
        skip(c, p, area.left + third * 0.5f, cy, r * 0.7f, glyph, back = true)
        p.color = ORANGE
        c.drawCircle(area.centerX(), cy, r, p)
        p.color = DECK
        if (playing) {
            val bw = r * 0.22f
            c.drawRoundRect(RectF(area.centerX() - r * 0.36f, cy - r * 0.42f, area.centerX() - r * 0.36f + bw, cy + r * 0.42f), bw * 0.3f, bw * 0.3f, p)
            c.drawRoundRect(RectF(area.centerX() + r * 0.36f - bw, cy - r * 0.42f, area.centerX() + r * 0.36f, cy + r * 0.42f), bw * 0.3f, bw * 0.3f, p)
        } else {
            val t = Path().apply {
                moveTo(area.centerX() - r * 0.3f, cy - r * 0.45f)
                lineTo(area.centerX() + r * 0.48f, cy)
                lineTo(area.centerX() - r * 0.3f, cy + r * 0.45f)
                close()
            }
            c.drawPath(t, p)
        }
        skip(c, p, area.right - third * 0.5f, cy, r * 0.7f, glyph, back = false)
    }

    private fun skip(c: Canvas, p: Paint, cx: Float, cy: Float, r: Float, color: Int, back: Boolean) {
        p.color = color
        val d = if (back) -1f else 1f
        val t = Path().apply {
            moveTo(cx - d * r * 0.55f, cy - r * 0.6f)
            lineTo(cx + d * r * 0.35f, cy)
            lineTo(cx - d * r * 0.55f, cy + r * 0.6f)
            close()
        }
        c.drawPath(t, p)
        val bar = r * 0.16f
        val bx = cx + d * r * 0.42f
        c.drawRoundRect(RectF(min(bx, bx + d * bar), cy - r * 0.6f, max(bx, bx + d * bar), cy + r * 0.6f), bar * 0.3f, bar * 0.3f, p)
    }

    // ------------------------------------------------------------------ the little tapes on the shelf

    /** A small cassette in a tape's own colors, with its name written on the label, [w]×[h] pixels. */
    fun shelfTape(context: Context, t: ShelfTape, w: Int, h: Int): Bitmap {
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        val nameRoom = h * 0.26f
        val cw = min(w * 0.94f, (h - nameRoom) * 1.574f)
        val ch = cw / 1.574f
        val x0 = (w - cw) / 2f
        val y0 = (h - nameRoom - ch) / 2f
        val look = t.colors
        val shell = RectF(x0, y0, x0 + cw, y0 + ch)
        val corner = cw * 0.06f
        p.color = 0x59000000
        p.maskFilter = BlurMaskFilter(max(1f, cw * 0.03f), BlurMaskFilter.Blur.NORMAL)
        c.drawRoundRect(RectF(shell.left + 1f, shell.top + ch * 0.06f, shell.right - 1f, shell.bottom + ch * 0.03f), corner, corner, p)
        p.maskFilter = null
        p.shade(LinearGradient(0f, shell.top, 0f, shell.bottom, mix(look.shell, Color.WHITE, 0.12f), mix(look.shell, Color.BLACK, 0.18f), Shader.TileMode.CLAMP))
        c.drawRoundRect(shell, corner, corner, p)
        p.shader = null
        val label = RectF(x0 + cw * 0.06f, y0 + ch * 0.08f, x0 + cw * 0.94f, y0 + ch * 0.7f)
        p.color = look.paper
        c.drawRoundRect(label, cw * 0.02f, cw * 0.02f, p)
        stripes(c, p, look, RectF(label.left, label.top + label.height() * 0.40f, label.right, label.top + label.height() * 0.585f))
        val wcy = label.top + label.height() * 0.735f
        reels(c, p, RectF(x0 + cw * 0.25f, wcy - ch * 0.1f, x0 + cw * 0.75f, wcy + ch * 0.1f), look, 0.35f)
        if (t.liked) {
            heart(c, label.left + label.height() * 0.24f, label.top + label.height() * 0.22f, label.height() * 0.16f, ORANGE)
        }
        p.color = if (light(look.shell)) mix(look.shell, Color.BLACK, 0.1f) else mix(look.shell, Color.WHITE, 0.08f)
        val t0 = y0 + ch * 0.78f
        c.drawPath(Path().apply {
            moveTo(x0 + cw * 0.22f, t0); lineTo(x0 + cw * 0.78f, t0)
            lineTo(x0 + cw * 0.83f, shell.bottom - 0.5f); lineTo(x0 + cw * 0.17f, shell.bottom - 0.5f); close()
        }, p)
        // the name under the tape, by hand
        val ink = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = CREAM
            typeface = handwriting(context)
            textAlign = Paint.Align.CENTER
        }
        val name = if (t.liked) "liked songs" else t.name
        ink.textSize = nameRoom * 0.78f
        var shown = name
        while (shown.length > 1 && ink.measureText(shown) > w * 0.96f) shown = shown.dropLast(1)
        if (shown != name) shown = shown.dropLast(1).trimEnd() + "…"
        c.drawText(shown, w / 2f, h - nameRoom * 0.22f, ink)
        return out
    }

    private fun heart(c: Canvas, cx: Float, cy: Float, size: Float, color: Int) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        val path = Path().apply {
            moveTo(cx, cy + size * 0.9f)
            cubicTo(cx - size * 1.4f, cy, cx - size * 0.9f, cy - size * 1.1f, cx, cy - size * 0.35f)
            cubicTo(cx + size * 0.9f, cy - size * 1.1f, cx + size * 1.4f, cy, cx, cy + size * 0.9f)
            close()
        }
        c.drawPath(path, p)
    }
}
