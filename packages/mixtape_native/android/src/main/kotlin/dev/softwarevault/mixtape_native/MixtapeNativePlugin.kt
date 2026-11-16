package dev.softwarevault.mixtape_native

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The bridge to Mixtape's Dart side on channel "mixtape/native". As a plugin it is there in every
 * Flutter engine, also the one audio_service starts by itself for a media button while the app is closed.
 */
class MixtapeNativePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware, PluginRegistry.NewIntentListener {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: ActivityPluginBinding? = null

    /** The tape a widget opened Mixtape with, until the app asks for it. */
    private var launched: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "mixtape/native")
        channel.setMethodCallHandler(this)
        live = channel
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        if (live === channel) live = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addOnNewIntentListener(this)
        Widgets.tapeOf(binding.activity.intent)?.let { launched = it }
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onDetachedFromActivity() {
        activity?.removeOnNewIntentListener(this)
        activity = null
    }

    /** A widget's tape tapped while Mixtape is open already. */
    override fun onNewIntent(intent: Intent): Boolean {
        val tape = Widgets.tapeOf(intent) ?: return false
        channel.invokeMethod("widget", tape)
        return true
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
            "phone" -> result.success(Phone.about(context))
            "askBatteryFree" -> result.success(Phone.askBatteryFree(context))
            "makerSettings" -> result.success(Phone.openMakerSettings(context))
            "widget" -> {
                val data = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                // the pictures take a moment to draw: not on the thread the app's screen runs on
                WORK.execute {
                    WidgetData.savePlaying(context, data)
                    Widgets.songChanged(context)
                }
                result.success(null)
            }
            "shelf" -> {
                val tapes = call.arguments as? List<*> ?: emptyList<Any>()
                WORK.execute {
                    WidgetData.saveShelf(context, tapes)
                    Widgets.shelfChanged(context)
                }
                result.success(null)
            }
            "widgetLaunch" -> {
                result.success(launched)
                launched = null
            }
            "widgetWaiting" -> result.success(WidgetData.takeWaiting(context))
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

        /** The channel of the engine that runs now, for what the widgets have to tell the app. */
        @Volatile
        private var live: MethodChannel? = null

        /** Tells the app [what] (on the main thread); false when no app runs to hear it. */
        fun tell(method: String, what: String): Boolean {
            val c = live ?: return false
            if (Looper.myLooper() == Looper.getMainLooper()) c.invokeMethod(method, what) else MAIN.post { c.invokeMethod(method, what) }
            return true
        }
    }
}
