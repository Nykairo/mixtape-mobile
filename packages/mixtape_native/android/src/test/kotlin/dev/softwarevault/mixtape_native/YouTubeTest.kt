package dev.softwarevault.mixtape_native

import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.HttpURLConnection
import java.net.URL

/**
 * The whole way a song takes, against the real YouTube: a search, the song's audio address, and the
 * first 64 kB of it fetched the way the app's player asks for them. Run by the build on GitHub, where it
 * only reports: YouTube treats servers in data centers more strictly than phones.
 */
class YouTubeTest {
    @Test
    fun searchResolveAndFetch() {
        YouTube.start("en", "US")
        val found = YouTube.search("daft punk get lucky")
        println("search: ${found.size} songs, first: ${found.firstOrNull()}")
        assertTrue("no songs found", found.isNotEmpty())

        val id = found.first()["id"] as String
        val song = YouTube.resolve(id)
        val related = song["related"] as List<*>
        println("resolve: ${song["mime"]}, ${song["bitrate"]} kbit/s, ${song["length"]} bytes, ${song["duration"]} s, " +
            "${related.size} songs like it, until ${song["expires"]}")

        val conn = URL(song["url"] as String).openConnection() as HttpURLConnection
        conn.setRequestProperty("Range", "bytes=0-65535")
        conn.setRequestProperty("User-Agent", song["agent"] as String)
        val code = conn.responseCode
        val got = (if (code < 400) conn.inputStream else conn.errorStream)?.use { it.readBytes().size } ?: 0
        println("fetch: HTTP $code, $got bytes, ${conn.getHeaderField("Content-Range")}")
        assertTrue("the audio didn't come (HTTP $code)", code == 206 || code == 200)
    }
}
