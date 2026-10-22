package com.screentimeguard.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/**
 * Android pil optimizasyonunun arka plan kontrolünü sonlandırmasını önlemek için
 * kalıcı bildirimle çalışan Foreground Service.
 * 60 saniyede bir UsageReader ile bugünkü süreyi okur ve Dart katmanına iletir.
 */
class MonitorService : Service() {

    companion object {
        private const val CHANNEL_ID = "screentime_guard_monitor"
        private const val NOTIFICATION_ID = 1001
        private const val CHECK_INTERVAL_MS = 60_000L // 60 saniye

        @Volatile
        var isRunning: Boolean = false
            private set
    }

    private val handler = Handler(Looper.getMainLooper())

    private val periodicCheckRunnable = object : Runnable {
        override fun run() {
            if (!isRunning) return

            val usageMap = UsageReader.readTodayUsage(applicationContext)
            val totalMinutes = (usageMap["total_minutes"] as? Int) ?: 0

            // Kalıcı bildirim üzerindeki güncel süreyi yenile
            updateForegroundNotification(totalMinutes)

            // Dart katmanındaki RuleEvaluator'a MethodChannel üzerinden ilet
            MainActivity.sendUsageTickToDart(usageMap)

            handler.postDelayed(this, CHECK_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createMonitorNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val initialUsage = UsageReader.readTodayUsage(applicationContext)
        val initialMinutes = (initialUsage["total_minutes"] as? Int) ?: 0

        startForeground(NOTIFICATION_ID, buildNotification(initialMinutes))
        isRunning = true

        handler.removeCallbacks(periodicCheckRunnable)
        handler.post(periodicCheckRunnable)

        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        handler.removeCallbacks(periodicCheckRunnable)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createMonitorNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Ekran Süresi İzleme Servisi",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Ekran kullanım süresini 60 saniyede bir kontrol eden arka plan servisi"
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(usedMinutes: Int): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setContentTitle("ScreenTime Guard Aktif")
            .setContentText("Bugünkü ekran süresi: $usedMinutes dk (60 sn'de bir kontrol ediliyor)")
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun updateForegroundNotification(usedMinutes: Int) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        manager?.notify(NOTIFICATION_ID, buildNotification(usedMinutes))
    }
}
