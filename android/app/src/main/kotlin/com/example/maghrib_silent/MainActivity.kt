package com.example.maghrib_silent

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "maghrib_silent/native")
            .setMethodCallHandler { call, result ->
                val nm = getSystemService(NotificationManager::class.java)
                val am = getSystemService(AlarmManager::class.java)
                val pm = getSystemService(PowerManager::class.java)
                when (call.method) {
                    "permissions" -> result.success(mapOf(
                        "dnd" to nm.isNotificationPolicyAccessGranted,
                        "exact" to (Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()),
                        "battery" to pm.isIgnoringBatteryOptimizations(packageName)
                    ))
                    "openDnd" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                        result.success(null)
                    }
                    "openExact" -> {
                        if (Build.VERSION.SDK_INT >= 31) startActivity(
                            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply { data = Uri.parse("package:$packageName") }
                        )
                        result.success(null)
                    }
                    "openBattery" -> {
                        try { startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) }
                        catch (_: Exception) {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply { data = Uri.parse("package:$packageName") })
                        }
                        result.success(null)
                    }
                    "scheduleQueue" -> {
                        val values = call.argument<List<Number>>("times")?.map { it.toLong() }
                        if (values.isNullOrEmpty()) result.error("QUEUE", "No Maghrib times supplied", null)
                        else { PrayerScheduler.setQueue(this, values); result.success(null) }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
