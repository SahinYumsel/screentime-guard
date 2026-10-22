package com.screentimeguard.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter (Dart) ile Kotlin native katmanı arasındaki MethodChannel köprüsü.
 * Kanal adı: "com.screentimeguard/native"
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL_NAME = "com.screentimeguard/native"
        private const val REQUEST_CODE_NOTIFICATIONS = 5001

        private var activeChannel: MethodChannel? = null

        /**
         * MonitorService tarafından her 60 saniyede bir çağrılır ve
         * güncel kullanım verisini Dart'taki RuleEvaluator'a iletir.
         */
        fun sendUsageTickToDart(usageMap: Map<String, Any>) {
            activeChannel?.invokeMethod("onUsageTick", usageMap)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        activeChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getTodayUsage" -> {
                    val data = UsageReader.readTodayUsage(applicationContext)
                    result.success(data)
                }

                "checkPermissions" -> {
                    val hasUsage = UsageReader.hasUsageStatsPermission(applicationContext)
                    val hasOverlay = OverlayManager.hasOverlayPermission(applicationContext)
                    val hasNotif = hasNotificationPermission()
                    val statusMap = mapOf(
                        "usageStats" to hasUsage,
                        "overlay" to hasOverlay,
                        "notifications" to hasNotif,
                        "monitoringActive" to MonitorService.isRunning
                    )
                    result.success(statusMap)
                }

                "openUsageAccessSettings" -> {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    startActivity(intent)
                    result.success(null)
                }

                "openOverlaySettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        ).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                    }
                    result.success(null)
                }

                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            REQUEST_CODE_NOTIFICATIONS
                        )
                    }
                    result.success(null)
                }

                "startMonitorService" -> {
                    val serviceIntent = Intent(applicationContext, MonitorService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        ContextCompat.startForegroundService(applicationContext, serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                    result.success(true)
                }

                "stopMonitorService" -> {
                    val serviceIntent = Intent(applicationContext, MonitorService::class.java)
                    stopService(serviceIntent)
                    result.success(true)
                }

                "triggerAlert" -> {
                    val args = call.arguments as? Map<*, *>
                    val title = args?.get("title")?.toString() ?: "ScreenTime Guard"
                    val message = args?.get("message")?.toString() ?: "Ekran süresi uyarısı!"
                    val mode = args?.get("mode")?.toString() ?: "notify"

                    if (mode == "overlay") {
                        OverlayManager.showOverlayAlert(applicationContext, title, message)
                    } else {
                        OverlayManager.showSystemNotification(applicationContext, title, message)
                    }
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (activeChannel != null) {
            activeChannel = null
        }
        super.onDestroy()
    }

    private fun hasNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }
}
