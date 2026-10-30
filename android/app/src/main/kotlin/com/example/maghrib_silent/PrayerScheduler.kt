package com.example.maghrib_silent

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import org.json.JSONArray

object PrayerScheduler {
    private const val PREF = "maghrib_native"
    private const val START = "com.example.maghrib_silent.START"
    private const val END = "com.example.maghrib_silent.END"
    private const val HALF_HOUR = 30 * 60 * 1000L
    private const val START_ID = 1001
    private const val END_ID = 1002

    private fun pending(context: Context, action: String, id: Int) =
        PendingIntent.getBroadcast(
            context, id, Intent(context, PrayerReceiver::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    fun setQueue(context: Context, values: List<Long>) {
        val json = JSONArray()
        values.forEach { json.put(it) }
        context.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit()
            .putString("times", json.toString())
            .putInt("index", 0)
            .apply()
        arm(context)
    }

    private fun times(context: Context): List<Long> {
        val raw = context.getSharedPreferences(PREF, Context.MODE_PRIVATE).getString("times", "[]") ?: "[]"
        val json = JSONArray(raw)
        return (0 until json.length()).map { json.getLong(it) }
    }

    fun arm(context: Context) {
        val prefs = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        val alarm = context.getSystemService(AlarmManager::class.java)
        alarm.cancel(pending(context, START, START_ID))
        alarm.cancel(pending(context, END, END_ID))

        if (Build.VERSION.SDK_INT >= 31 && !alarm.canScheduleExactAlarms()) return
        val now = System.currentTimeMillis()

        if (prefs.getBoolean("active", false)) {
            val endAt = prefs.getLong("activeEnd", 0L)
            if (endAt > now) alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endAt, pending(context, END, END_ID))
            else onEnd(context)
            return
        }

        val queue = times(context)
        var index = prefs.getInt("index", 0)
        while (index < queue.size && queue[index] + HALF_HOUR <= now) index++
        prefs.edit().putInt("index", index).apply()
        if (index >= queue.size) return

        val startAt = queue[index]
        if (startAt > now) alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, startAt, pending(context, START, START_ID))
        alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, startAt + HALF_HOUR, pending(context, END, END_ID))
    }

    fun onStart(context: Context) {
        val prefs = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        if (prefs.getBoolean("active", false)) return
        val queue = times(context)
        val index = prefs.getInt("index", 0)
        if (index >= queue.size) return

        val nm = context.getSystemService(NotificationManager::class.java)
        val audio = context.getSystemService(AudioManager::class.java)
        val endAt = queue[index] + HALF_HOUR
        prefs.edit()
            .putInt("previousRinger", audio.ringerMode)
            .putInt("previousFilter", nm.currentInterruptionFilter)
            .putLong("activeEnd", endAt)
            .putBoolean("active", true)
            .commit()

        if (nm.isNotificationPolicyAccessGranted) {
            nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE)
        }
        arm(context)
    }

    fun onEnd(context: Context) {
        val prefs = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        if (prefs.getBoolean("active", false)) {
            val nm = context.getSystemService(NotificationManager::class.java)
            val audio = context.getSystemService(AudioManager::class.java)
            if (nm.isNotificationPolicyAccessGranted) {
                nm.setInterruptionFilter(prefs.getInt("previousFilter", NotificationManager.INTERRUPTION_FILTER_ALL))
            }
            try {
                audio.ringerMode = prefs.getInt("previousRinger", AudioManager.RINGER_MODE_NORMAL)
            } catch (_: SecurityException) { }
            prefs.edit().putBoolean("active", false).remove("activeEnd").apply()
        }
        prefs.edit().putInt("index", prefs.getInt("index", 0) + 1).apply()
        arm(context)
    }
}
