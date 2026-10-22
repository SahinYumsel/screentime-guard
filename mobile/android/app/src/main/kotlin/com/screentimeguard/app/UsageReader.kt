package com.screentimeguard.app

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Process
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Android UsageStatsManager kullanarak bugünün (00:00'dan şu ana kadar)
 * toplam ekran kullanım süresini ve en çok kullanılan ilk 5 uygulamayı okur.
 */
object UsageReader {

    /**
     * Kullanıcının Ayarlar -> Kullanım Verisi Erişimi (PACKAGE_USAGE_STATS)
     * iznini verip vermediğini AppOpsManager üzerinden kontrol eder.
     */
    fun hasUsageStatsPermission(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            ?: return false
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /**
     * Bugünkü kullanım süresini okur ve Dart katmanının (UsageRecord.fromJson)
     * beklediği Map yapısında döndürür:
     * {
     *   "date": "2026-10-22",
     *   "total_minutes": 143,
     *   "top_apps": [{"package": "com.instagram.android", "minutes": 52}, ...]
     * }
     */
    fun readTodayUsage(context: Context): Map<String, Any> {
        val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val todayStr = dateFormat.format(Date())

        if (!hasUsageStatsPermission(context)) {
            return mapOf(
                "date" to todayStr,
                "total_minutes" to 0,
                "top_apps" to emptyList<Map<String, Any>>()
            )
        }

        val usageStatsManager =
            context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
                ?: return mapOf(
                    "date" to todayStr,
                    "total_minutes" to 0,
                    "top_apps" to emptyList<Map<String, Any>>()
                )

        // Bugün gece yarısı (00:00:00.000) -> Şu an
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val startOfDayMillis = calendar.timeInMillis
        val nowMillis = System.currentTimeMillis()

        val rawStats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            startOfDayMillis,
            nowMillis
        ) ?: emptyList()

        // Aynı paket için birden fazla aralık kaydı dönebileceğinden süreleri paket bazında topla
        val packageMillisMap = mutableMapOf<String, Long>()
        for (stat in rawStats) {
            // Sadece bugün içinde kullanılan ve ön planda süresi olan paketleri dahil et
            if (stat.lastTimeUsed >= startOfDayMillis && stat.totalTimeInForeground > 0L) {
                val current = packageMillisMap[stat.packageName] ?: 0L
                packageMillisMap[stat.packageName] = current + stat.totalTimeInForeground
            }
        }

        // Milisaniyeyi dakikaya çevir ve 1 dakikadan az olanları filtrele
        val appMinutesList = packageMillisMap.entries
            .map { entry ->
                val minutes = (entry.value / 60_000L).toInt()
                entry.key to minutes
            }
            .filter { (_, minutes) -> minutes > 0 }
            .sortedByDescending { (_, minutes) -> minutes }

        val totalMinutes = appMinutesList.sumOf { (_, minutes) -> minutes }

        val topApps = appMinutesList.take(5).map { (pkg, minutes) ->
            mapOf(
                "package" to pkg,
                "minutes" to minutes
            )
        }

        return mapOf(
            "date" to todayStr,
            "total_minutes" to totalMinutes,
            "top_apps" to topApps
        )
    }
}
