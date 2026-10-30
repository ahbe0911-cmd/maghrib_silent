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
    private fun openSettings(vararg intents: Intent): Boolean {
        for (intent in intents) {
            try {
                startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: Exception) { }
        }
        return false
    }

    private fun appDetails() = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
        data = Uri.parse("package:$packageName")
    }

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
                    "openDnd" -> result.success(openSettings(
                        Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS),
                        appDetails()
                    ))
                    "openExact" -> result.success(
                        if (Build.VERSION.SDK_INT < 31) true else openSettings(
                            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                                data = Uri.parse("package:$packageName")
                            },
                            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM),
                            appDetails()
                        )
                    )
                    "openBattery" -> result.success(openSettings(
                        Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.parse("package:$packageName")
                        },
                        Intent(Settings.ACTION_SETTINGS)
                    ))
                    "scheduleQueue" -> {
                        val values = call.argument<List<Number>>("times")?.map { it.toLong() }
                        if (values.isNullOrEmpty()) result.error("QUEUE", "No Maghrib times supplied", null)
                        else { PrayerScheduler.setQueue(this, values); result.success(null) }
                    }
                    "testDnd" -> result.success(PrayerScheduler.testNow(this))
                    else -> result.notImplemented()
                }
            }
    }
}
