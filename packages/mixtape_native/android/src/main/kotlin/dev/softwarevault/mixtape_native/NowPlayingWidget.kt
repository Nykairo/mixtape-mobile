package dev.softwarevault.mixtape_native

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.view.KeyEvent
import android.widget.RemoteViews
import java.io.File
import kotlin.math.max

/**
 * Mixtape on the home screen: the song that plays, with its cover glued onto a little cassette, and
 * keys for the song before, play or pause, and the next one. The keys go to audio_service's media button
 * receiver, so they work while the app itself is closed. The app tells the widget what plays (show);
 * a tap anywhere else opens Mixtape.
 */
class NowPlayingWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        draw(context, manager, ids)
    }

    companion object {
        private const val PREFS = "mixtape_widget"

        fun show(context: Context, title: String, artist: String, playing: Boolean, art: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("title", title)
                .putString("artist", artist)
                .putBoolean("playing", playing)
                .putString("art", art)
                .apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, NowPlayingWidget::class.java))
            if (ids.isNotEmpty()) draw(context, manager, ids)
        }

        private fun draw(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val title = prefs.getString("title", "") ?: ""
            val artist = prefs.getString("artist", "") ?: ""
            val playing = prefs.getBoolean("playing", false)
            val art = prefs.getString("art", "") ?: ""
            val views = RemoteViews(context.packageName, R.layout.mixtape_widget)
            views.setTextViewText(R.id.mixtape_widget_title, title.ifEmpty { "Nothing playing" })
            views.setTextViewText(R.id.mixtape_widget_artist, artist.ifEmpty { "Press play in Mixtape" })
            views.setImageViewBitmap(R.id.mixtape_widget_tape, cassette(cover(art)))
            views.setImageViewResource(R.id.mixtape_widget_play,
                if (playing) R.drawable.mixtape_widget_pause else R.drawable.mixtape_widget_play)
            views.setOnClickPendingIntent(R.id.mixtape_widget_prev, key(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
            views.setOnClickPendingIntent(R.id.mixtape_widget_play, key(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
            views.setOnClickPendingIntent(R.id.mixtape_widget_next, key(context, KeyEvent.KEYCODE_MEDIA_NEXT))
            context.packageManager.getLaunchIntentForPackage(context.packageName)?.let { launch ->
                views.setOnClickPendingIntent(R.id.mixtape_widget_root,
                    PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_IMMUTABLE))
            }
            manager.updateAppWidget(ids, views)
        }

        /** A media key, as if pressed on a headset: audio_service's receiver takes it from there. */
        private fun key(context: Context, code: Int): PendingIntent {
            val intent = Intent(Intent.ACTION_MEDIA_BUTTON)
                .setComponent(ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver"))
                .putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, code))
            return PendingIntent.getBroadcast(context, code, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }

        private fun cover(path: String): Bitmap? {
            if (path.isEmpty() || !File(path).isFile) return null
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            var sample = 1
            while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 256) sample *= 2
            return BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
        }

        /**
         * The little cassette: warm black plastic, the cream label with the three stripes, the window with
         * the reels, and the song's cover glued onto the label like a photo. Drawn once per song.
         */
        private fun cassette(art: Bitmap?): Bitmap {
            val w = 420f
            val h = w / 1.574f
            val bmp = Bitmap.createBitmap(w.toInt(), h.toInt(), Bitmap.Config.ARGB_8888)
            val c = Canvas(bmp)
            val p = Paint(Paint.ANTI_ALIAS_FLAG)
            p.shader = LinearGradient(0f, 0f, 0f, h, 0xFF3B322C.toInt(), 0xFF1D1713.toInt(), Shader.TileMode.CLAMP)
            c.drawRoundRect(RectF(0f, 0f, w, h), w * 0.045f, w * 0.045f, p)
            p.shader = null
            val label = RectF(w * 0.06f, h * 0.075f, w * 0.94f, h * 0.705f)
            p.shader = LinearGradient(0f, label.top, 0f, label.bottom, 0xFFF1E6CF.toInt(), 0xFFE2D6BF.toInt(),
                Shader.TileMode.CLAMP)
            c.drawRoundRect(label, w * 0.016f, w * 0.016f, p)
            p.shader = null
            var top = label.top + label.height() * 0.40f
            for ((color, frac) in listOf(0xFFFF6A1A.toInt() to 0.085f, 0xFFFFA323.toInt() to 0.06f, 0xFFFFD567.toInt() to 0.04f)) {
                p.color = color
                c.drawRect(label.left, top, label.right, top + label.height() * frac, p)
                top += label.height() * frac
            }
            val cy = label.top + label.height() * 0.735f
            val window = RectF(w * 0.23f, cy - h * 0.1025f, w * 0.77f, cy + h * 0.1025f)
            p.color = 0xFF0E0B09.toInt()
            c.drawRoundRect(window, window.height() * 0.3f, window.height() * 0.3f, p)
            c.save()
            c.clipRect(window)
            for ((fx, pack) in listOf(0.31f to w * 0.11f, 0.69f to w * 0.075f)) {
                val x = w * fx
                p.shader = RadialGradient(x, cy, pack, intArrayOf(0xFF140D08.toInt(), 0xFF2C1B10.toInt(),
                    0xFF3B2618.toInt(), 0xFF1A1009.toInt()), floatArrayOf(0f, 0.5f, 0.9f, 1f), Shader.TileMode.CLAMP)
                c.drawCircle(x, cy, pack, p)
                p.shader = null
                p.color = 0xFFE9E0CF.toInt()
                c.drawCircle(x, cy, w * 0.05f, p)
                p.color = 0xFF120E0B.toInt()
                c.drawCircle(x, cy, w * 0.03f, p)
            }
            c.restore()
            if (art != null) {
                // the cover, glued on at a slight angle at the label's right end
                val s = label.height() * 0.62f
                c.save()
                c.translate(label.right - s * 0.62f, label.top + s * 0.55f)
                c.rotate(-4f)
                p.color = 0x55000000
                c.drawRect(-s / 2 + 2f, -s / 2 + 3f, s / 2 + 2f, s / 2 + 3f, p)
                p.color = 0xFFFBF8F1.toInt()
                c.drawRect(-s / 2, -s / 2, s / 2, s / 2, p)
                val inner = s - 8f
                val shader = BitmapShader(art, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
                val scale = max(inner / art.width, inner / art.height)
                shader.setLocalMatrix(Matrix().apply {
                    setScale(scale, scale)
                    postTranslate(-art.width * scale / 2, -art.height * scale / 2)
                })
                p.shader = shader
                c.drawRect(-inner / 2, -inner / 2, inner / 2, inner / 2, p)
                p.shader = null
                c.restore()
            }
            return bmp
        }
    }
}
