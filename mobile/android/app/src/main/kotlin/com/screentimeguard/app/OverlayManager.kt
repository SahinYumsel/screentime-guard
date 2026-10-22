package com.screentimeguard.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Kural ihlali durumlarında (warn_80, limit_exceeded, in_cutoff_window)
 * kullanıcıya sistem bildirimi (notify) veya ekran üstü pencere (overlay) gösterir.
 */
object OverlayManager {

    private const val ALERT_CHANNEL_ID = "screentime_guard_alerts"
    private const val ALERT_NOTIFICATION_ID = 2002

    private var activeOverlayView: View? = null

    fun hasOverlayPermission(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }
    }

    /**
     * Standart yüksek öncelikli sistem bildirimi gönderir (mode == "notify" veya overlay izni yoksa).
     */
    fun showSystemNotification(context: Context, title: String, message: String) {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                ALERT_CHANNEL_ID,
                "Ekran Süresi Uyarıları",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Günlük limit aşımı ve kesme saati bildirimleri"
            }
            manager.createNotificationChannel(channel)
        }

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(context, ALERT_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(context)
        }

        val notification = builder
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(android.app.Notification.BigTextStyle().bigText(message))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        manager.notify(ALERT_NOTIFICATION_ID, notification)
    }

    /**
     * Açık uygulamanın üzerinde (WindowManager TYPE_APPLICATION_OVERLAY) uyarı penceresi gösterir.
     * Eğer kullanıcı SYSTEM_ALERT_WINDOW izni vermemişse güvenli şekilde sistem bildirimine düşer.
     */
    fun showOverlayAlert(context: Context, title: String, message: String) {
        if (!hasOverlayPermission(context)) {
            showSystemNotification(context, title, message)
            return
        }

        // Zaten açık bir overlay varsa önce kaldır
        dismissOverlay(context)

        val windowManager =
            context.applicationContext.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
                ?: return

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutType,
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
        }

        val density = context.resources.displayMetrics.density
        val pad = (24 * density).toInt()

        val cardBackground = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = 16f * density
            setColor(Color.parseColor("#1E1E2E"))
            setStroke((2 * density).toInt(), Color.parseColor("#FF6B6B"))
        }

        val container = LinearLayout(context.applicationContext).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad, pad, pad)
            background = cardBackground
        }

        val titleView = TextView(context.applicationContext).apply {
            text = title
            textSize = 19f
            setTextColor(Color.parseColor("#FF6B6B"))
            setPadding(0, 0, 0, (10 * density).toInt())
        }

        val messageView = TextView(context.applicationContext).apply {
            text = message
            textSize = 15f
            setTextColor(Color.WHITE)
            setPadding(0, 0, 0, (18 * density).toInt())
        }

        val closeButton = Button(context.applicationContext).apply {
            text = "Anladım / Kapat"
            setBackgroundColor(Color.parseColor("#4F46E5"))
            setTextColor(Color.WHITE)
            setOnClickListener {
                dismissOverlay(context.applicationContext)
            }
        }

        container.addView(titleView)
        container.addView(messageView)
        container.addView(closeButton)

        try {
            windowManager.addView(container, params)
            activeOverlayView = container
        } catch (_: Exception) {
            showSystemNotification(context, title, message)
        }
    }

    fun dismissOverlay(context: Context) {
        val view = activeOverlayView ?: return
        val windowManager =
            context.applicationContext.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        try {
            windowManager?.removeView(view)
        } catch (_: Exception) {
        } finally {
            activeOverlayView = null
        }
    }
}
