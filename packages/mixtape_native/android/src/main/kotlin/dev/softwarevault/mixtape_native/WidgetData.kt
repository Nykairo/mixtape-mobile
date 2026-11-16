package dev.softwarevault.mixtape_native

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** A tape's colors, the way the app draws that cassette (TapeLook in cassette.dart). */
internal data class TapeColors(
    val shell: Int,
    val shellAlpha: Int,
    val paper: Int,
    val ink: Int,
    val stripes: List<Int>,
    val stripeStyle: String,
    val hub: Int,
    val tape: Int,
    val screw: Int,
    val screws: Boolean,
) {
    companion object {
        /** Mixtape's own cassette: warm black, cream label, the three stripes. */
        val PLAIN = TapeColors(
            shell = 0xFF2E2621.toInt(), shellAlpha = 255, paper = 0xFFF1E6CF.toInt(), ink = 0xFF25428E.toInt(),
            stripes = listOf(0xFFFF6A1A.toInt(), 0xFFFFA323.toInt(), 0xFFFFD567.toInt()), stripeStyle = "classic",
            hub = 0xFFECE4D4.toInt(), tape = 0xFF3B2618.toInt(), screw = 0xFFB9B4AC.toInt(), screws = true,
        )

        fun from(j: JSONObject?): TapeColors? {
            if (j == null) return null
            fun color(key: String, or: Int) = if (j.has(key)) j.optLong(key).toInt() else or
            val stripes = j.optJSONArray("stripes")
            return TapeColors(
                shell = color("shell", PLAIN.shell),
                shellAlpha = j.optInt("shellAlpha", 255),
                paper = color("paper", PLAIN.paper),
                ink = color("ink", PLAIN.ink),
                stripes = if (stripes == null || stripes.length() == 0) PLAIN.stripes
                else List(stripes.length()) { stripes.optLong(it).toInt() },
                stripeStyle = j.optString("stripeStyle", "classic"),
                hub = color("hub", PLAIN.hub),
                tape = color("tape", PLAIN.tape),
                screw = color("screw", PLAIN.screw),
                screws = j.optBoolean("screws", true),
            )
        }
    }
}

/** What plays, as the app last said. [at] is when [position] was true (System.currentTimeMillis). */
internal data class Playing(
    val id: String,
    val title: String,
    val artist: String,
    val playing: Boolean,
    val art: String,
    val liked: Boolean,
    val shuffle: Boolean,
    val position: Long,
    val duration: Long,
    val at: Long,
    val index: Int,
    val count: Int,
    val tape: String,
    val colors: TapeColors?,
    val track: JSONObject?,
) {
    /** How far into the tape (or the queue) the music is, 0 to 1: the reels show it. */
    val along: Float get() = if (count <= 0) 0f else ((index + 0.5f) / count).coerceIn(0f, 1f)
}

/** One tape on the "My tapes" widget. */
internal data class ShelfTape(val id: String, val name: String, val songs: Int, val colors: TapeColors, val liked: Boolean)

/**
 * What the home screen widgets show, kept in the app's preferences: a launcher that redraws a widget
 * after the phone restarts gets the same picture. Also the likes tapped on a widget while the app
 * wasn't running, which the app takes in when it starts.
 */
internal object WidgetData {
    private const val PREFS = "mixtape_widget"

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun savePlaying(context: Context, data: Map<*, *>) {
        prefs(context).edit().putString("playing", JSONObject(data).put("at", System.currentTimeMillis()).toString()).apply()
    }

    fun playing(context: Context): Playing? {
        val raw = prefs(context).getString("playing", null) ?: return null
        return try {
            val j = JSONObject(raw)
            Playing(
                id = j.optString("id"),
                title = j.optString("title"),
                artist = j.optString("artist"),
                playing = j.optBoolean("playing"),
                art = j.optString("art"),
                liked = j.optBoolean("liked"),
                shuffle = j.optBoolean("shuffle"),
                position = j.optLong("position"),
                duration = j.optLong("duration"),
                at = j.optLong("at", System.currentTimeMillis()),
                index = j.optInt("index"),
                count = j.optInt("count"),
                tape = j.optString("tape"),
                colors = TapeColors.from(j.optJSONObject("colors")),
                track = j.optJSONObject("track"),
            )
        } catch (e: Exception) {
            null
        }
    }

    /** A heart or shuffle tapped on a widget: shown at once, before the app has even heard of it. */
    fun flip(context: Context, what: String) {
        val raw = prefs(context).getString("playing", null) ?: return
        val j = try {
            JSONObject(raw)
        } catch (e: Exception) {
            return
        }
        when (what) {
            "like" -> j.put("liked", !j.optBoolean("liked"))
            "shuffle" -> j.put("shuffle", !j.optBoolean("shuffle"))
            else -> return
        }
        prefs(context).edit().putString("playing", j.toString()).apply()
    }

    fun saveShelf(context: Context, tapes: List<*>) {
        prefs(context).edit().putString("shelf", JSONArray(tapes).toString()).apply()
    }

    fun shelf(context: Context): List<ShelfTape> {
        val raw = prefs(context).getString("shelf", null) ?: return emptyList()
        return try {
            val a = JSONArray(raw)
            List(a.length()) { k ->
                val j = a.getJSONObject(k)
                ShelfTape(
                    id = j.optString("id"),
                    name = j.optString("name"),
                    songs = j.optInt("songs"),
                    colors = TapeColors.from(j.optJSONObject("colors")) ?: TapeColors.PLAIN,
                    liked = j.optBoolean("liked"),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /** A like for the song on the widget, tapped while the app was closed: the app does it when it starts. */
    fun keepLike(context: Context, track: JSONObject, liked: Boolean) {
        val list = JSONArray(prefs(context).getString("waiting", "[]"))
        list.put(JSONObject().put("track", track).put("liked", liked))
        prefs(context).edit().putString("waiting", list.toString()).apply()
    }

    fun takeWaiting(context: Context): String {
        val raw = prefs(context).getString("waiting", "[]") ?: "[]"
        prefs(context).edit().remove("waiting").apply()
        return raw
    }
}
