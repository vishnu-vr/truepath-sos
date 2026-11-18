package app.truepath.truepath_care

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * SOS alarm support.
 *
 * - When the activity is launched by a notification (the SOS full-screen
 *   intent uses action SELECT_NOTIFICATION from flutter_local_notifications),
 *   it is allowed over the lock screen and turns the screen on. This is NOT
 *   set in the manifest on purpose: otherwise the whole app would be
 *   readable over the lock screen at any time. Flutter clears it via
 *   `setAlarmMode(false)` when the alarm screen closes.
 * - `status` / `open*` back the in-app "Alarm setup" checklist.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "truepath/alarm"

    override fun onCreate(savedInstanceState: Bundle?) {
        applyAlarmMode(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        applyAlarmMode(intent)
        super.onNewIntent(intent)
    }

    private fun applyAlarmMode(intent: Intent?) {
        if (intent?.action == "SELECT_NOTIFICATION") setAlarmMode(true)
    }

    private fun setAlarmMode(on: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(on)
            setTurnScreenOn(on)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setAlarmMode" -> {
                        setAlarmMode(call.arguments as? Boolean ?: false)
                        result.success(null)
                    }
                    "status" -> result.success(status())
                    "openFullScreenSettings" -> {
                        if (Build.VERSION.SDK_INT >= 34) {
                            open(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                Uri.parse("package:$packageName")))
                        } else {
                            openAppDetails()
                        }
                        result.success(null)
                    }
                    "openDndSettings" -> {
                        open(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                        result.success(null)
                    }
                    "openBatterySettings" -> {
                        val ok = open(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                            Uri.parse("package:$packageName")))
                        if (!ok) open(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        result.success(null)
                    }
                    "openNotificationSettings" -> {
                        open(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                        result.success(null)
                    }
                    "openAppDetails" -> {
                        openAppDetails()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun status(): Map<String, Any> {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return mapOf(
            "sdk" to Build.VERSION.SDK_INT,
            "manufacturer" to Build.MANUFACTURER,
            "notifications" to nm.areNotificationsEnabled(),
            "fullScreen" to (Build.VERSION.SDK_INT < 34 || nm.canUseFullScreenIntent()),
            "dnd" to nm.isNotificationPolicyAccessGranted,
            "battery" to pm.isIgnoringBatteryOptimizations(packageName),
        )
    }

    private fun openAppDetails() {
        open(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
    }

    private fun open(intent: Intent): Boolean = try {
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }
}
