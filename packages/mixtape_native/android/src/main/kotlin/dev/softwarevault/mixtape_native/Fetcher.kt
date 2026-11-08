package dev.softwarevault.mixtape_native

import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.GZIPInputStream

/**
 * How NewPipe's extractor reaches YouTube: Android's own HttpURLConnection, so no HTTP library has to
 * come along. The extractor's headers win over the defaults set here.
 */
class Fetcher : Downloader() {

    override fun execute(request: Request): Response {
        val conn = URL(request.url()).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = request.httpMethod()
            conn.connectTimeout = 10_000
            conn.readTimeout = 20_000
            conn.instanceFollowRedirects = true
            conn.setRequestProperty("User-Agent", USER_AGENT)
            conn.setRequestProperty("Accept-Encoding", "gzip")
            for ((name, values) in request.headers()) {
                values.forEachIndexed { k, value ->
                    if (k == 0) conn.setRequestProperty(name, value) else conn.addRequestProperty(name, value)
                }
            }
            val body = request.dataToSend()
            if (body != null) {
                conn.doOutput = true
                conn.outputStream.use { it.write(body) }
            }
            val code = conn.responseCode
            if (code == 429) {
                throw ReCaptchaException("YouTube asked for a captcha", request.url())
            }
            val stream = if (code >= 400) conn.errorStream else conn.inputStream
            val text = stream?.let { raw ->
                val unpacked = if ("gzip".equals(conn.contentEncoding, ignoreCase = true)) GZIPInputStream(raw) else raw
                unpacked.use { it.readBytes().toString(Charsets.UTF_8) }
            } ?: ""
            val headers = conn.headerFields.entries
                .filter { it.key != null }
                .associate { it.key to it.value }
            return Response(code, conn.responseMessage ?: "", headers, text, conn.url.toString())
        } finally {
            conn.disconnect()
        }
    }

    companion object {
        const val USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"
    }
}
