package com.example.maghrib_silent

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build

object PrayerScheduler {
    private const val PREF = "maghrib_native"
    const val START = "com.example.maghrib_silent.START"
    const val END = "com.example.maghrib_silent.END"
    private const val HALF_HOUR = 30 * 60 * 1000L

    private fun pending(context: Context, action: String, code: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            code,
            Intent(context, PrayerReceiver::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    fun schedule(context: Context, startMs: Long, nextStartMs: Long) {
        val prefs = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        prefs.edit().putLong("start", startMs).putLong("next", nextStartMs).apply()
        arm(context)
    }

    fun arm(context: Context) {
        val prefs = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        val start = prefs.getLong("start", 0)
        val next = prefs.getLong("next", 0)
        val alarm = context.getSystemService(AlarmManager::class.java)
        alarm.cancel(pending(context, START, 1001))
        alarm.cancel(pending(context, END, 1002))
        if (Build.VERSION.SDK_INT >= 31 && !alarm.canScheduleExactAlarms()) return

        val now = System.currentTimeMillis()
        val chosen = if (start + HALF_HOUR > now) start else next
        if (chosen <= 0 || chosen + HALF_HOUR <= now) return

        if (chosen > now) {
            alarm.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                chosen,
                pending(context, START, 1001)
            )
        }
        alarm.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            chosen + HALF_HOUR,
            pending(context, END, 1002)
        )
    }

    fun onStart(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java)
        if (!nm.isNotificationPolicyAccessGranted) return
        val prefs = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        if (prefs.getBoolean("active", false)) return

        val audio = context.getSystemService(AudioManager::class.java)
        prefs.edit()
            .putInt("previousRinger", audio.ringerMode)
            .putInt("previousFilter", nm.currentInterruptionFilter)
            .putBoolean("active", true)
            .commit()

        nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE)
    }

    fun onEnd(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java)
        val prefs = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("active", false)) return
        if (!nm.isNotificationPolicyAccessGranted) return

        val audio = context.getSystemService(AudioManager::class.java)
        val filter = prefs.getInt(
            "previousFilter",
            NotificationManager.INTERRUPTION_FILTER_ALL
        )
        val ringer = prefs.getInt("previousRinger", AudioManager.RINGER_MODE_NORMAL)

        nm.setInterruptionFilter(filter)
        try {
            audio.ringerMode = ringer
        } catch (_: SecurityException) {
        }
        prefs.edit().putBoolean("active", false).apply()
    }

    fun active(context: Context): Boolean =
        context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
            .getBoolean("active", false)
}
