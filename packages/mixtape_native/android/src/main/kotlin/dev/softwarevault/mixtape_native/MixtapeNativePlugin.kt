package dev.softwarevault.mixtape_native

import android.app.Activity
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
class MixtapeNativePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware, PluginRegistry.NewIntentListener,
    PluginRegistry.ActivityResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: ActivityPluginBinding? = null

    /** The answer waiting for a picture to be picked (a profile picture). */
    private var picking: MethodChannel.Result? = null

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
        binding.addActivityResultListener(this)
        Widgets.tapeOf(binding.activity.intent)?.let { launched = it }
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onDetachedFromActivity() {
        activity?.removeOnNewIntentListener(this)
        activity?.removeActivityResultListener(this)
        activity = null
    }

    /** The picture picked (or none): made into a profile picture away from the main thread. */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_PICTURE) return false
        val answer = picking ?: return true
        picking = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            answer.success(null)
            return true
        }
        offMain(answer) { ProfilePicture.from(context, uri) }
        return true
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
            "shareImage" -> {
                // the picture is copied into the shared folder first, so only it can be read from there
                val from = java.io.File(call.argument<String>("path") ?: "")
                if (!from.isFile) {
                    result.success(false)
                } else {
                    val folder = SharedFiles.folder(context)
                    folder.listFiles()?.forEach { if (System.currentTimeMillis() - it.lastModified() > 3_600_000) it.delete() }
                    val file = java.io.File(folder, from.name)
                    from.copyTo(file, overwrite = true)
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "image/png"
                        putExtra(Intent.EXTRA_STREAM, SharedFiles.uriOf(context, file))
                        call.argument<String>("text")?.let { putExtra(Intent.EXTRA_TEXT, it) }
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    val chooser = Intent.createChooser(send, null).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    val here = activity?.activity
                    if (here != null) here.startActivity(chooser) else context.startActivity(chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
            }
            "pickPicture" -> {
                val here = activity?.activity
                if (here == null || picking != null) {
                    result.success(null)
                } else {
                    picking = result
                    val pick = Intent(Intent.ACTION_GET_CONTENT).apply {
                        type = "image/*"
                        addCategory(Intent.CATEGORY_OPENABLE)
                    }
                    here.startActivityForResult(Intent.createChooser(pick, null), PICK_PICTURE)
                }
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
        private const val PICK_PICTURE = 0x6D78 // "mx", a number no other plugin picks for its results
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
