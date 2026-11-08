package dev.softwarevault.mixtape_native

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The bridge to Mixtape's Dart side on channel "mixtape/native". As a plugin it is there in every
 * Flutter engine, also the one audio_service starts by itself for a media button while the app is closed.
 */
class MixtapeNativePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "mixtape/native")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "search" -> offMain(result) { started().search(call.argument<String>("query") ?: "") }
            "resolve" -> offMain(result) { started().resolve(call.argument<String>("id") ?: "") }
            "video" -> offMain(result) { started().video(call.argument<String>("id") ?: "") }
            "share" -> {
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "")
                }
                val chooser = Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(chooser)
                result.success(null)
            }
            "widget" -> {
                NowPlayingWidget.show(
                    context,
                    call.argument<String>("title") ?: "",
                    call.argument<String>("artist") ?: "",
                    call.argument<Boolean>("playing") ?: false,
                    call.argument<String>("art") ?: "",
                )
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun started(): YouTube {
        val here = Locale.getDefault()
        YouTube.start(here.language.ifEmpty { "en" }, here.country.ifEmpty { "US" })
        return YouTube
    }

    /** YouTube calls block for a while: they run on a few threads of their own, the answer comes back on the main one. */
    private fun offMain(result: MethodChannel.Result, job: () -> Any?) {
        WORK.execute {
            try {
                val value = job()
                MAIN.post { result.success(value) }
            } catch (e: Throwable) {
                MAIN.post { result.error(YouTube.why(e), e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    companion object {
        private val WORK: ExecutorService = Executors.newFixedThreadPool(3)
        private val MAIN = Handler(Looper.getMainLooper())
    }
}
