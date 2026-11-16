package dev.softwarevault.mixtape_native

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.text.format.DateUtils
import android.util.SizeF
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Mixtape's widgets for the home screen: the Cassette, Now playing, Cover, Mini player and My tapes.
 * The app tells them what plays (WidgetData); the keys send media keys to audio_service's receiver,
 * so they work while the app itself is closed, and a tap anywhere else opens Mixtape.
 */
abstract class MixtapeWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) draw(context, manager, id)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        draw(context, manager, id)
    }

    /** The widget at [size], in dp. */
    internal abstract fun views(context: Context, size: SizeF): RemoteViews

    fun draw(context: Context, manager: AppWidgetManager, id: Int) {
        val sizes = Widgets.sizes(context, manager, id)
        val views = if (Build.VERSION.SDK_INT >= 31 && sizes.size > 1) {
            RemoteViews(sizes.associateWith { views(context, it) })
        } else {
            views(context, sizes.first())
        }
        try {
            manager.updateAppWidget(id, views)
        } catch (e: Exception) {
            // the launcher went away meanwhile; it asks again when it's back
        }
    }
}

/** The song on a little cassette: the cover glued on its label, the title by hand, the keys in its head. */
class CassetteWidget : MixtapeWidget() {
    override fun views(context: Context, size: SizeF): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.mixtape_widget_cassette)
        val s = WidgetData.playing(context)
        val d = Widgets.density(context)
        val w = (size.width * d).roundToInt().coerceIn(120, 1400)
        val h = (size.height * d).roundToInt().coerceIn(80, 1000)
        val (art, keys) = WidgetArt.cassette(context, s, w, h, d)
        v.setImageViewBitmap(R.id.mixtape_cassette_art, art)
        v.setContentDescription(R.id.mixtape_cassette_art, Widgets.said(context, s))
        // the three keys go over the cassette's head: where that is in the picture, in the view's pixels
        val real = context.resources.displayMetrics.density
        val f = real / d
        val viewW = size.width * real
        val viewH = size.height * real
        v.setViewPadding(
            R.id.mixtape_cassette_keys,
            (keys.area.left * f).roundToInt(),
            (keys.area.top * f).roundToInt(),
            max(0, (viewW - keys.area.right * f).roundToInt()),
            max(0, (viewH - keys.area.bottom * f).roundToInt()),
        )
        v.setOnClickPendingIntent(R.id.mixtape_cassette_prev, Widgets.key(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
        v.setOnClickPendingIntent(R.id.mixtape_cassette_play, Widgets.key(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
        v.setOnClickPendingIntent(R.id.mixtape_cassette_next, Widgets.key(context, KeyEvent.KEYCODE_MEDIA_NEXT))
        Widgets.open(context)?.let { v.setOnClickPendingIntent(R.id.mixtape_cassette_art, it) }
        return v
    }
}

/** Now playing, the way Spotify and YouTube Music show it: the cover big, its colors behind everything. */
class NowPlayingWidget : MixtapeWidget() {
    override fun views(context: Context, size: SizeF): RemoteViews {
        val small = size.height < 100f
        val v = RemoteViews(context.packageName, if (small) R.layout.mixtape_widget_now_small else R.layout.mixtape_widget_now)
        val s = WidgetData.playing(context)
        val d = Widgets.density(context)
        // the cover as big as the card is high, as long as the song and its keys keep their room beside it
        // (150dp, or the song and two keys in the low one); left out where it would only be a stamp
        val coverDp = if (small) min(size.height - 20f, size.width - 20f - 12f - 170f) else min(size.height - 28f, size.width - 28f - 14f - 150f)
        val coverPx = (max(coverDp, 48f) * d).roundToInt().coerceIn(48, 600)
        val src = WidgetArt.cover(s?.art ?: "", coverPx)
        Widgets.cover(context, v, R.id.mixtape_now_cover, if (coverDp >= 56f) WidgetArt.rounded(src, coverPx, coverPx * 0.1f) else null, coverDp)
        v.setImageViewBitmap(R.id.mixtape_now_back,
            WidgetArt.backdrop(src, (size.width * d).roundToInt(), (size.height * d).roundToInt(), Widgets.corner(d)))
        Widgets.song(context, v, s, R.id.mixtape_now_title, R.id.mixtape_now_artist)
        Widgets.play(context, v, s, R.id.mixtape_now_play)
        v.setOnClickPendingIntent(R.id.mixtape_now_next, Widgets.key(context, KeyEvent.KEYCODE_MEDIA_NEXT))
        if (!small) {
            v.setOnClickPendingIntent(R.id.mixtape_now_prev, Widgets.key(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
            v.setImageViewResource(R.id.mixtape_now_like, if (s?.liked == true) R.drawable.mixtape_widget_heart_on else R.drawable.mixtape_widget_heart)
            v.setImageViewResource(R.id.mixtape_now_shuffle, if (s?.shuffle == true) R.drawable.mixtape_widget_shuffle_on else R.drawable.mixtape_widget_shuffle)
            v.setOnClickPendingIntent(R.id.mixtape_now_like, Widgets.action(context, "like"))
            v.setOnClickPendingIntent(R.id.mixtape_now_shuffle, Widgets.action(context, "shuffle"))
            Widgets.clock(v, s, R.id.mixtape_now_time, R.id.mixtape_now_length)
        }
        Widgets.open(context)?.let { v.setOnClickPendingIntent(R.id.mixtape_now_root, it) }
        return v
    }
}

/** Just the cover, the song along its bottom and a round play key. */
class CoverWidget : MixtapeWidget() {
    override fun views(context: Context, size: SizeF): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.mixtape_widget_cover)
        val s = WidgetData.playing(context)
        val d = Widgets.density(context)
        val w = (size.width * d).roundToInt().coerceIn(96, 900)
        val h = (size.height * d).roundToInt().coerceIn(96, 900)
        v.setImageViewBitmap(R.id.mixtape_cover_art, WidgetArt.coverCard(WidgetArt.cover(s?.art ?: "", max(w, h)), w, h, Widgets.corner(d)))
        v.setContentDescription(R.id.mixtape_cover_art, Widgets.said(context, s))
        // the name and the key side by side need about 150dp; on a smaller one the key is enough
        v.setViewVisibility(R.id.mixtape_cover_name, if (size.width >= 150f) View.VISIBLE else View.GONE)
        Widgets.song(context, v, s, R.id.mixtape_cover_title, R.id.mixtape_cover_artist)
        Widgets.play(context, v, s, R.id.mixtape_cover_play)
        Widgets.open(context)?.let { v.setOnClickPendingIntent(R.id.mixtape_cover_root, it) }
        return v
    }
}

/** One slim row: the cover, the song, play and next. */
class MiniWidget : MixtapeWidget() {
    override fun views(context: Context, size: SizeF): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.mixtape_widget_mini)
        val s = WidgetData.playing(context)
        val d = Widgets.density(context)
        val coverDp = min(size.height, 120f) - 16f
        val px = (coverDp * d).roundToInt().coerceIn(32, 320)
        // on a narrow one the song needs the room more than the cover does
        val picture = if (size.width >= 230f) WidgetArt.rounded(WidgetArt.cover(s?.art ?: "", px), px, px * 0.16f) else null
        Widgets.cover(context, v, R.id.mixtape_mini_cover, picture, coverDp)
        Widgets.song(context, v, s, R.id.mixtape_mini_title, R.id.mixtape_mini_artist)
        Widgets.play(context, v, s, R.id.mixtape_mini_play)
        v.setOnClickPendingIntent(R.id.mixtape_mini_next, Widgets.key(context, KeyEvent.KEYCODE_MEDIA_NEXT))
        Widgets.open(context)?.let { v.setOnClickPendingIntent(R.id.mixtape_mini_root, it) }
        return v
    }
}

/** My tapes: little cassettes in their own colors, as many as there's room for; a tap plays one. */
class TapesWidget : MixtapeWidget() {
    override fun views(context: Context, size: SizeF): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.mixtape_widget_tapes)
        val tapes = WidgetData.shelf(context)
        val cols = (size.width / 84f).toInt().coerceIn(2, 4)
        val rows = if (size.height >= 150f) 2 else 1
        val shown = tapes.take(cols * rows)
        v.setViewVisibility(R.id.mixtape_tapes_empty, if (shown.isEmpty()) View.VISIBLE else View.GONE)
        v.setViewVisibility(R.id.mixtape_tapes_row0, if (shown.isEmpty()) View.GONE else View.VISIBLE)
        v.setViewVisibility(R.id.mixtape_tapes_row1, if (rows == 2 && shown.size > cols) View.VISIBLE else View.GONE)
        val d = Widgets.density(context)
        val cellW = ((size.width - 20f) / cols * d).roundToInt().coerceIn(40, 600)
        val cellH = ((size.height - 38f) / rows * d).roundToInt().coerceIn(40, 600)
        for (k in CELLS.indices) {
            val row = k / 4
            val col = k % 4
            val slot = row * cols + col
            when {
                col >= cols -> v.setViewVisibility(CELLS[k], View.GONE)
                row >= rows || slot >= shown.size -> v.setViewVisibility(CELLS[k], View.INVISIBLE)
                else -> {
                    val t = shown[slot]
                    v.setViewVisibility(CELLS[k], View.VISIBLE)
                    v.setImageViewBitmap(CELLS[k], WidgetArt.shelfTape(context, t, cellW, cellH))
                    v.setContentDescription(CELLS[k], if (t.liked) "Liked songs" else t.name)
                    Widgets.openTape(context, t.id)?.let { v.setOnClickPendingIntent(CELLS[k], it) }
                }
            }
        }
        if (shown.isEmpty()) Widgets.open(context)?.let { v.setOnClickPendingIntent(R.id.mixtape_tapes_root, it) }
        return v
    }

    private companion object {
        val CELLS = intArrayOf(
            R.id.mixtape_tapes_0, R.id.mixtape_tapes_1, R.id.mixtape_tapes_2, R.id.mixtape_tapes_3,
            R.id.mixtape_tapes_4, R.id.mixtape_tapes_5, R.id.mixtape_tapes_6, R.id.mixtape_tapes_7,
        )
    }
}

/** Like and shuffle tapped on a widget: the app does them while it runs, and a like waits for it otherwise. */
class WidgetActions : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val what = intent.getStringExtra("what") ?: return
        val now = WidgetData.playing(context)
        WidgetData.flip(context, what)
        if (!MixtapeNativePlugin.tell("widget", what) && what == "like" && now?.track != null) {
            WidgetData.keepLike(context, now.track, !now.liked)
        }
        Widgets.songChanged(context)
    }
}

internal object Widgets {
    const val ACTION_TAPE = "dev.softwarevault.mixtape.PLAY_TAPE"
    const val EXTRA_TAPE = "mixtape_tape"
    private const val ACTION_WIDGET = "dev.softwarevault.mixtape.WIDGET"

    private val SONG = listOf(CassetteWidget::class.java, NowPlayingWidget::class.java, CoverWidget::class.java, MiniWidget::class.java)

    /** Redraws every widget that shows the song. */
    fun songChanged(context: Context) {
        val manager = AppWidgetManager.getInstance(context) ?: return
        for (kind in SONG) redraw(context, manager, kind)
    }

    fun shelfChanged(context: Context) {
        val manager = AppWidgetManager.getInstance(context) ?: return
        redraw(context, manager, TapesWidget::class.java)
    }

    private fun redraw(context: Context, manager: AppWidgetManager, kind: Class<out MixtapeWidget>) {
        val ids = manager.getAppWidgetIds(ComponentName(context, kind))
        if (ids.isEmpty()) return
        val widget = kind.getDeclaredConstructor().newInstance()
        for (id in ids) widget.draw(context, manager, id)
    }

    /**
     * The sizes the launcher gives a widget, in dp. Android 12 and newer list each one it may show (a
     * tablet that turns has two); a phone stays upright, so its upright size is enough there and saves
     * drawing every picture twice. Before Android 12: the one for how the phone is held.
     */
    fun sizes(context: Context, manager: AppWidgetManager, id: Int): List<SizeF> {
        val o = manager.getAppWidgetOptions(id)
        if (Build.VERSION.SDK_INT >= 31) {
            @Suppress("DEPRECATION")
            val list = o.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
            if (!list.isNullOrEmpty()) {
                val tablet = context.resources.configuration.smallestScreenWidthDp >= 600
                return if (tablet) list.distinct() else listOf(list.maxBy { it.height })
            }
        }
        val upright = context.resources.configuration.orientation != Configuration.ORIENTATION_LANDSCAPE
        val w = o.getInt(if (upright) AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH)
        val h = o.getInt(if (upright) AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
        return listOf(SizeF(if (w > 0) w.toFloat() else 250f, if (h > 0) h.toFloat() else 110f))
    }

    /** Pixels per dp for the pictures: the phone's own, up to 3 (sharp anywhere, never heavier than needed). */
    fun density(context: Context) = min(context.resources.displayMetrics.density, 3f)

    /**
     * The corners to cut into a picture that fills a widget's card. Android 12 and newer cut them on the
     * launcher's side (clipToOutline, in the launcher's own radius); before that nothing does, so the
     * picture brings the card's 24dp corners itself.
     */
    fun corner(d: Float) = if (Build.VERSION.SDK_INT >= 31) 0f else 24f * d

    /** A cover beside the song, [dp] big at most; [picture] null leaves it out and gives the song the room. */
    fun cover(context: Context, v: RemoteViews, id: Int, picture: Bitmap?, dp: Float) {
        if (picture == null) {
            v.setViewVisibility(id, View.GONE)
            return
        }
        v.setViewVisibility(id, View.VISIBLE)
        v.setImageViewBitmap(id, picture)
        v.setInt(id, "setMaxWidth", (dp * context.resources.displayMetrics.density).roundToInt())
    }

    fun said(context: Context, s: Playing?): String =
        if (s == null || s.title.isEmpty()) context.getString(R.string.mixtape_widget_nothing) else "${s.title}, ${s.artist}"

    fun song(context: Context, v: RemoteViews, s: Playing?, title: Int, artist: Int) {
        v.setTextViewText(title, s?.title?.ifEmpty { null } ?: context.getString(R.string.mixtape_widget_nothing))
        v.setTextViewText(artist, s?.artist?.ifEmpty { null } ?: context.getString(R.string.mixtape_widget_press_play))
    }

    fun play(context: Context, v: RemoteViews, s: Playing?, id: Int) {
        v.setImageViewResource(id, if (s?.playing == true) R.drawable.mixtape_widget_pause else R.drawable.mixtape_widget_play)
        v.setOnClickPendingIntent(id, key(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
    }

    /** The time into the song, ticking by itself on the launcher's side (nothing here wakes up for it), and its length. */
    fun clock(v: RemoteViews, s: Playing?, time: Int, length: Int) {
        if (s == null || s.duration <= 0) {
            v.setViewVisibility(time, View.GONE)
            v.setTextViewText(length, "")
            return
        }
        v.setViewVisibility(time, View.VISIBLE)
        val at = if (s.playing) s.position + (System.currentTimeMillis() - s.at) else s.position
        v.setChronometer(time, SystemClock.elapsedRealtime() - at.coerceIn(0, s.duration), null, s.playing)
        // written the way the Chronometer writes its own time, so the two match (01:23 / 03:34)
        v.setTextViewText(length, "  /  " + DateUtils.formatElapsedTime(s.duration / 1000))
    }

    /** A media key, as if pressed on a headset: audio_service's receiver takes it from there. */
    fun key(context: Context, code: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON)
            .setComponent(ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver"))
            .putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, code))
        return PendingIntent.getBroadcast(context, code, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /** Opens Mixtape. */
    fun open(context: Context): PendingIntent? {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
        return PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /** Opens Mixtape on a tape, which then plays. */
    fun openTape(context: Context, id: String): PendingIntent? {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
        launch.action = ACTION_TAPE
        launch.putExtra(EXTRA_TAPE, id)
        launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(context, 1000 + (id.hashCode() and 0xFFFF), launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /** Like or shuffle, for WidgetActions. */
    fun action(context: Context, what: String): PendingIntent {
        val intent = Intent(context, WidgetActions::class.java).setAction("$ACTION_WIDGET.$what").putExtra("what", what)
        return PendingIntent.getBroadcast(context, what.hashCode() and 0xFFFF, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /** The tape a widget opened Mixtape with ("tape:<id>"), taken out of the intent so it plays once. */
    fun tapeOf(intent: Intent?): String? {
        if (intent == null || intent.action != ACTION_TAPE) return null
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null // back from recents: not a new tap
        val id = intent.getStringExtra(EXTRA_TAPE) ?: return null
        intent.removeExtra(EXTRA_TAPE)
        intent.action = Intent.ACTION_MAIN
        return "tape:$id"
    }
}
