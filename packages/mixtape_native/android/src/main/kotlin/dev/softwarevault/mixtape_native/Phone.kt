package dev.softwarevault.mixtape_native

import android.annotation.SuppressLint
import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import java.util.Locale

/**
 * What the phone's maker does to an app that plays with the screen off. Plain Android leaves music
 * alone, but the battery managers of Xiaomi, Huawei, Honor, Oppo, Realme, OnePlus, Vivo, Samsung and
 * a few others stop it after a while all the same, unless the app is let off in their own settings.
 * These are the places they keep those settings (the list dontkillmyapp.com keeps, in short).
 */
object Phone {
    /** The maker as one word ("xiaomi" for Redmi and POCO too, "transsion" for Tecno, Infinix and itel). */
    fun maker(): String {
        val m = Build.MANUFACTURER.lowercase(Locale.ROOT)
        val b = Build.BRAND.lowercase(Locale.ROOT)
        fun any(vararg names: String) = names.any { m.contains(it) || b.contains(it) }
        return when {
            any("xiaomi", "redmi", "poco") -> "xiaomi"
            any("honor") -> "honor"
            any("huawei") -> "huawei"
            any("oneplus") -> "oneplus"
            any("realme") -> "realme"
            any("oppo") -> "oppo"
            any("vivo", "iqoo") -> "vivo"
            any("samsung") -> "samsung"
            any("tecno", "infinix", "itel") -> "transsion"
            any("motorola", "lenovo") -> "motorola"
            any("google") -> "google"
            any("nothing") -> "nothing"
            any("asus") -> "asus"
            any("hmd", "nokia") -> "nokia"
            any("sony") -> "sony"
            any("zte", "nubia") -> "zte"
            any("meizu") -> "meizu"
            else -> m.substringBefore(' ')
        }
    }

    /** Whether Android's battery saving already leaves Mixtape alone. */
    fun batteryFree(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(context.packageName)
    }

    /** Asks for that with the phone's own little dialog, or opens the list where it's set. */
    @SuppressLint("BatteryLife")
    fun askBatteryFree(context: Context): Boolean =
        open(context, Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:" + context.packageName))) ||
            open(context, Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))

    /** The maker's own page for apps in the background, or failing that Mixtape's page in Settings. */
    fun openMakerSettings(context: Context): Boolean {
        for ((pkg, cls) in PLACES[maker()].orEmpty()) {
            if (open(context, Intent().setComponent(ComponentName(pkg, cls)))) return true
        }
        return open(context, Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + context.packageName)))
    }

    /** A phone with little memory (Android Go, or under 3 GB): the app keeps fewer pictures around. */
    fun lowRam(context: Context): Boolean {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo()
        am.getMemoryInfo(info)
        return am.isLowRamDevice || info.totalMem in 1L until 3L * 1024 * 1024 * 1024
    }

    fun about(context: Context): Map<String, Any> = mapOf(
        "maker" to maker(),
        "brand" to Build.BRAND,
        "model" to Build.MODEL,
        "android" to Build.VERSION.SDK_INT,
        "batteryFree" to batteryFree(context),
        "lowRam" to lowRam(context),
    )

    /** Starts a settings page; false when this phone hasn't got it (or won't let us in). */
    private fun open(context: Context, intent: Intent): Boolean = try {
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false  // ActivityNotFoundException where the page isn't there, SecurityException where it's private
    }

    /** Where each maker keeps it, newest first; the first one this phone opens wins. */
    private val PLACES: Map<String, List<Pair<String, String>>> = mapOf(
        "xiaomi" to listOf(
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
            "com.miui.powerkeeper" to "com.miui.powerkeeper.ui.HiddenAppsConfigActivity",
        ),
        "huawei" to listOf(
            "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
        ),
        "honor" to listOf(
            "com.hihonor.systemmanager" to "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
        ),
        "oppo" to COLOROS,
        "realme" to COLOROS,
        "oneplus" to listOf("com.oneplus.security" to "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity") + COLOROS,
        "vivo" to listOf(
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
        ),
        "transsion" to listOf("com.transsion.phonemaster" to "com.cyin.himgr.autostart.AutoStartActivity"),
        "asus" to listOf(
            "com.asus.mobilemanager" to "com.asus.mobilemanager.autostart.AutoStartActivity",
            "com.asus.mobilemanager" to "com.asus.mobilemanager.entry.FunctionActivity",
        ),
        "nokia" to listOf("com.evenwell.powersaving.g3" to "com.evenwell.powersaving.g3.exception.PowerSaverExceptionActivity"),
        // Samsung: Mixtape's own page has Battery > Unrestricted, which is the switch that counts
    )

    private val COLOROS: List<Pair<String, String>>
        get() = listOf(
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
            "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
            "com.coloros.oppoguardelf" to "com.coloros.powermanager.fuelgaue.PowerUsageModelActivity",
        )
}
