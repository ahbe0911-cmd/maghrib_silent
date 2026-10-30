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
    private val channel = "maghrib_silent/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                val nm = getSystemService(NotificationManager::class.java)
                val am = getSystemService(AlarmManager::class.java)
                val pm = getSystemService(PowerManager::class.java)
                when (call.method) {
                    "permissions" -> result.success(
                        mapOf(
                            "dnd" to nm.isNotificationPolicyAccessGranted,
                            "exact" to (Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()),
                            "battery" to pm.isIgnoringBatteryOptimizations(packageName)
                        )
                    )
                    "openDnd" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                        result.success(null)
                    }
                    "openExact" -> {
                        if (Build.VERSION.SDK_INT >= 31) {
                            try {
                                startActivity(
                                    Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                                        data = Uri.parse("package:$packageName")
                                    }
                                )
                            } catch (_: Exception) {
                                startActivity(
                                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                        data = Uri.parse("package:$packageName")
                                    }
                                )
                            }
                        }
                        result.success(null)
                    }
                    "openBattery" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        } catch (_: Exception) {
                            startActivity(
                                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                            )
                        }
                        result.success(null)
                    }
                    "schedule" -> {
                        val start = call.argument<Number>("start")?.toLong()
                        val next = call.argument<Number>("next")?.toLong()
                        if (start == null || next == null) {
                            result.error("ARG", "Missing times", null)
                        } else {
                            PrayerScheduler.schedule(this, start, next)
                            result.success(null)
                        }
                    }
                    "active" -> result.success(PrayerScheduler.active(this))
                    else -> result.notImplemented()
                }
            }
    }
}
