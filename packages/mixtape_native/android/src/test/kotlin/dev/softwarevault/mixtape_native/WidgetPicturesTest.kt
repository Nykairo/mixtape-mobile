package dev.softwarevault.mixtape_native

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.util.SizeF
import android.view.View
import android.widget.FrameLayout
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.io.FileOutputStream
import kotlin.math.roundToInt

/**
 * Pictures of every widget in a few sizes, drawn by the very code the phone runs (Robolectric with real
 * graphics), on a home screen's wallpaper; and each one alone for the widget picker's previews.
 *
 *     WIDGET_PICTURES=<folder> WIDGET_FONT=<CoveredByYourGrace.ttf> ./gradlew :mixtape_native:testDebugUnitTest --tests '*WidgetPictures*'
 *
 * Without WIDGET_PICTURES it does nothing.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w384dp-h832dp-xxhdpi")
class WidgetPicturesTest {

    @Test
    fun pictures() {
        val folder = System.getenv("WIDGET_PICTURES") ?: return
        val out = File(folder).apply { mkdirs() }
        val context: Context = RuntimeEnvironment.getApplication()
        System.getenv("WIDGET_FONT")?.let { if (File(it).isFile) WidgetArt.hand = Typeface.createFromFile(it) }

        val cover = File(out, "sample-cover.png")
        FileOutputStream(cover).use { sampleCover().compress(Bitmap.CompressFormat.PNG, 100, it) }

        // a song from a sunset-colored tape, three songs in out of eight
        WidgetData.savePlaying(context, mapOf(
            "id" to "dQw4w9WgXcQ", "title" to "Night Drive", "artist" to "The Reels", "playing" to true,
            "art" to cover.path, "liked" to true, "shuffle" to false, "position" to 83_000L, "duration" to 214_000L,
            "index" to 2, "count" to 8, "tape" to "Road trip",
            "colors" to colors(0xFF2E2621, 0xFFF4D35E, 0xFF1F1A16, listOf(0xFFFF6A1A, 0xFFFFA323, 0xFFFFD567), "classic"),
        ))
        WidgetData.saveShelf(context, listOf(
            tape("", "Liked songs", 0xFF2E2621, 0xFFF1E6CF, "classic", liked = true),
            tape("Road trip", "Road trip", 0xFFB2342A, 0xFFF4D35E, "band"),
            tape("Rainy days", "rainy days", 0xFF335F9E, 0xFFDDEBF5, "lines"),
            tape("Gym", "gym", 0xFF2E2621, 0xFFE8E3D8, "fade"),
            tape("Sunday", "sunday morning", 0xFFE8E3D8, 0xFFF7B9C9, "classic"),
            tape("Night", "night drive", 0xFF684A9C, 0xFF2B2240, "none"),
        ))

        val cassette = CassetteWidget()
        val now = NowPlayingWidget()
        val coverWidget = CoverWidget()
        val mini = MiniWidget()
        val tapes = TapesWidget()
        val home = listOf(
            listOf(Placed(cassette, SizeF(356f, 170f))),
            listOf(Placed(coverWidget, SizeF(170f, 170f)), Placed(tapes, SizeF(170f, 170f))),
            listOf(Placed(now, SizeF(356f, 170f))),
            listOf(Placed(mini, SizeF(356f, 76f))),
        )
        save(homeScreen(context, home), File(out, "widgets-home.png"))
        // each one alone, in its usual size and made bigger or smaller
        for ((name, widget, sizes) in listOf(
            Triple("cassette", cassette, listOf(SizeF(356f, 170f), SizeF(270f, 130f), SizeF(356f, 260f))),
            Triple("now", now, listOf(SizeF(356f, 170f), SizeF(356f, 80f), SizeF(270f, 150f))),
            Triple("cover", coverWidget, listOf(SizeF(170f, 170f), SizeF(130f, 130f))),
            Triple("mini", mini, listOf(SizeF(356f, 76f), SizeF(270f, 60f))),
            Triple("tapes", tapes, listOf(SizeF(170f, 170f), SizeF(356f, 170f), SizeF(356f, 90f))),
        )) {
            for ((k, size) in sizes.withIndex()) {
                save(alone(context, widget, size, wallpaper = true), File(out, "widget-$name-${k + 1}.png"))
            }
            save(alone(context, widget, sizes.first(), wallpaper = false), File(out, "preview-$name.png"))
        }
        // a light tape that's paused, and a long name, the way some songs are called
        WidgetData.savePlaying(context, mapOf(
            "id" to "x", "title" to "Everything Everywhere All at Once (Extended Mix)", "artist" to "A Band With a Very Long Name",
            "playing" to false, "art" to cover.path, "liked" to false, "shuffle" to true, "position" to 3_000L, "duration" to 3_725_000L,
            "index" to 7, "count" to 8, "tape" to "Sunday",
            "colors" to colors(0xFFE8E3D8, 0xFFF7B9C9, 0xFF25428E, listOf(0xFFFF6A1A, 0xFFFFA323, 0xFFFFD567), "band"),
        ))
        save(alone(context, cassette, SizeF(356f, 170f), wallpaper = true), File(out, "widget-cassette-light.png"))
        save(alone(context, now, SizeF(356f, 170f), wallpaper = true), File(out, "widget-now-long.png"))
        save(alone(context, coverWidget, SizeF(170f, 170f), wallpaper = true), File(out, "widget-cover-long.png"))
        save(alone(context, mini, SizeF(250f, 60f), wallpaper = true), File(out, "widget-mini-narrow.png"))

        // nothing played yet, and no tapes
        WidgetData.savePlaying(context, mapOf("title" to "", "artist" to "", "playing" to false))
        WidgetData.saveShelf(context, emptyList<Any>())
        save(homeScreen(context, home), File(out, "widgets-home-empty.png"))
    }

    private class Placed(val widget: MixtapeWidget, val size: SizeF)

    private fun colors(shell: Long, paper: Long, ink: Long, stripes: List<Long>, style: String) = mapOf(
        "shell" to shell, "shellAlpha" to 255, "paper" to paper, "ink" to ink, "stripes" to stripes,
        "stripeStyle" to style, "hub" to 0xFFECE4D4, "tape" to 0xFF3B2618, "screw" to 0xFFB9B4AC, "screws" to true,
    )

    private fun tape(id: String, name: String, shell: Long, paper: Long, style: String, liked: Boolean = false) = mapOf(
        "id" to id, "name" to name, "songs" to 12, "liked" to liked,
        "colors" to colors(shell, paper, 0xFF25428E, listOf(0xFFFF6A1A, 0xFFFFA323, 0xFFFFD567), style),
    )

    /** A cover to show: a sunset over the sea, drawn here (no real album art in the repository). */
    private fun sampleCover(): Bitmap {
        val s = 544
        val b = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.shader = LinearGradient(0f, 0f, 0f, s.toFloat(), intArrayOf(0xFF2B1145.toInt(), 0xFFA62D5C.toInt(), 0xFFFF8A3C.toInt()), null, Shader.TileMode.CLAMP)
        c.drawRect(0f, 0f, s.toFloat(), s.toFloat(), p)
        p.shader = RadialGradient(s * 0.5f, s * 0.62f, s * 0.22f, 0xFFFFE08A.toInt(), 0xFFFF9A2E.toInt(), Shader.TileMode.CLAMP)
        c.drawCircle(s * 0.5f, s * 0.62f, s * 0.22f, p)
        p.shader = null
        p.color = 0xFF1A0E2A.toInt()
        c.drawRect(0f, s * 0.7f, s.toFloat(), s.toFloat(), p)
        p.color = 0x55FFB35A
        for (k in 0 until 6) c.drawRect(s * (0.3f + k * 0.02f), s * (0.72f + k * 0.04f), s * (0.7f - k * 0.02f), s * (0.735f + k * 0.04f), p)
        return b
    }

    /** The widget as the launcher shows it: its views made from the RemoteViews and drawn at [size]. */
    private fun render(context: Context, widget: MixtapeWidget, size: SizeF): Bitmap {
        val views = widget.views(context, size)
        val view = views.apply(context, FrameLayout(context))
        val d = context.resources.displayMetrics.density
        val w = (size.width * d).roundToInt()
        val h = (size.height * d).roundToInt()
        view.measure(View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY))
        view.layout(0, 0, w, h)
        val b = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        view.draw(Canvas(b))
        // what a launcher does on Android 12 and newer and a drawing without one can't: the card's
        // corners cut along its outline (clipToOutline)
        if (!view.clipToOutline) return b
        val outline = Outline()
        view.outlineProvider?.getOutline(view, outline)
        val box = Rect()
        if (!outline.getRect(box)) return b
        val cut = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(cut)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        c.drawRoundRect(RectF(box), outline.radius, outline.radius, p)
        p.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        c.drawBitmap(b, 0f, 0f, p)
        return cut
    }

    private fun wallpaper(c: Canvas, w: Float, h: Float) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.shader = LinearGradient(0f, 0f, w, h, intArrayOf(0xFF1C2541.toInt(), 0xFF3A2440.toInt(), 0xFF24151F.toInt()), null, Shader.TileMode.CLAMP)
        c.drawRect(0f, 0f, w, h, p)
        p.shader = RadialGradient(w * 0.2f, h * 0.1f, w * 0.9f, 0x663B4F7A, 0x003B4F7A, Shader.TileMode.CLAMP)
        c.drawRect(0f, 0f, w, h, p)
    }

    private fun alone(context: Context, widget: MixtapeWidget, size: SizeF, wallpaper: Boolean): Bitmap {
        val w = render(context, widget, size)
        if (!wallpaper) return w
        val pad = (16 * context.resources.displayMetrics.density).roundToInt()
        val b = Bitmap.createBitmap(w.width + 2 * pad, w.height + 2 * pad, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        wallpaper(c, b.width.toFloat(), b.height.toFloat())
        c.drawBitmap(w, pad.toFloat(), pad.toFloat(), null)
        return b
    }

    /** A phone's home screen with the widgets in rows, the way a Galaxy lays them out. */
    private fun homeScreen(context: Context, rows: List<List<Placed>>): Bitmap {
        val d = context.resources.displayMetrics.density
        val width = (384 * d).roundToInt()
        val gap = 14 * d
        val height = (rows.sumOf { r -> r.maxOf { it.size.height }.toDouble() } * d + gap * (rows.size + 1) + 60 * d).roundToInt()
        val b = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        wallpaper(c, width.toFloat(), height.toFloat())
        var y = 40 * d
        for (row in rows) {
            var x = 14 * d
            for (placed in row) {
                c.drawBitmap(render(context, placed.widget, placed.size), x, y, null)
                x += placed.size.width * d + 16 * d
            }
            y += row.maxOf { it.size.height } * d + gap
        }
        return b
    }

    private fun save(b: Bitmap, file: File) {
        FileOutputStream(file).use { b.compress(Bitmap.CompressFormat.PNG, 100, it) }
        println("picture: ${file.name} ${b.width}x${b.height}")
    }
}
