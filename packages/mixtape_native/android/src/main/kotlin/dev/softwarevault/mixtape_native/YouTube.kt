package dev.softwarevault.mixtape_native

import org.schabi.newpipe.extractor.InfoItem
import org.schabi.newpipe.extractor.MediaFormat
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.exceptions.AgeRestrictedContentException
import org.schabi.newpipe.extractor.exceptions.ContentNotAvailableException
import org.schabi.newpipe.extractor.exceptions.GeographicRestrictionException
import org.schabi.newpipe.extractor.exceptions.PaidContentException
import org.schabi.newpipe.extractor.exceptions.PrivateContentException
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import org.schabi.newpipe.extractor.exceptions.SignInConfirmNotBotException
import org.schabi.newpipe.extractor.localization.ContentCountry
import org.schabi.newpipe.extractor.localization.Localization
import org.schabi.newpipe.extractor.services.youtube.YoutubeParsingHelper
import org.schabi.newpipe.extractor.services.youtube.linkHandler.YoutubeSearchQueryHandlerFactory
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import java.io.IOException

/**
 * YouTube Music for Mixtape, through NewPipe's extractor: song search, songs like a song (its radio)
 * and, for playing, the address a song's audio streams from. Every call blocks, so the plugin runs them
 * off the main thread.
 */
object YouTube {
    @Volatile
    private var started = false

    fun start(language: String, country: String) {
        if (started) return
        synchronized(this) {
            if (!started) {
                NewPipe.init(Fetcher(), Localization(language, country), ContentCountry(country))
                started = true
            }
        }
    }

    /** Songs on YouTube Music for a search, the way its app lists them under Songs. */
    fun search(query: String): List<Map<String, Any?>> {
        val extractor = ServiceList.YouTube.getSearchExtractor(
            query, listOf(YoutubeSearchQueryHandlerFactory.MUSIC_SONGS), "")
        extractor.fetchPage()
        return extractor.initialPage.items.mapNotNull { song(it) }
    }

    /** Where a song's audio comes from right now: the best plain audio file (AAC first, it plays everywhere). */
    fun resolve(id: String): Map<String, Any?> {
        val info = StreamInfo.getInfo(ServiceList.YouTube, "https://www.youtube.com/watch?v=$id")
        val plain = info.audioStreams.filter { it.isUrl && it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP }
        val best = plain.filter { it.format == MediaFormat.M4A }.maxByOrNull { it.averageBitrate }
            ?: plain.maxByOrNull { it.averageBitrate }
            ?: throw IOException("no plain audio stream")
        val related = info.relatedItems.mapNotNull { song(it) }.take(25)
        return mapOf(
            "url" to best.content,
            "mime" to (best.format?.mimeType ?: "audio/mp4"),
            "bitrate" to best.averageBitrate,
            "length" to (best.itagItem?.contentLength ?: -1L),
            "duration" to info.duration,
            "agent" to YoutubeParsingHelper.getVisionOsUserAgent(null),
            "expires" to expiry(best.content),
            "related" to related,
        )
    }

    /** A short word for why a song can't be had, for the app to say it in its own words. */
    fun why(e: Throwable): String = when (e) {
        is AgeRestrictedContentException -> "age"
        is GeographicRestrictionException -> "region"
        is PrivateContentException -> "private"
        is PaidContentException -> "members"
        is SignInConfirmNotBotException, is ReCaptchaException -> "busy"
        is ContentNotAvailableException -> "gone"
        is IOException -> "network"
        else -> "trouble"
    }

    private fun song(item: InfoItem): Map<String, Any?>? {
        if (item !is StreamInfoItem) return null
        val id = idOf(item.url) ?: return null
        val art = item.thumbnails.maxByOrNull { it.height }?.url ?: ""
        return mapOf(
            "id" to id,
            "title" to item.name,
            "artist" to (item.uploaderName ?: "").removeSuffix(" - Topic"),
            "art" to art,
            "dur" to item.duration,
        )
    }

    private fun idOf(url: String): String? =
        Regex("""[?&]v=([\w-]{11})""").find(url)?.groupValues?.get(1)
            ?: Regex("""youtu\.be/([\w-]{11})""").find(url)?.groupValues?.get(1)

    private fun expiry(url: String): Long =
        Regex("""[?&]expire=(\d+)""").find(url)?.groupValues?.get(1)?.toLongOrNull()
            ?: (System.currentTimeMillis() / 1000 + 3600)
}
