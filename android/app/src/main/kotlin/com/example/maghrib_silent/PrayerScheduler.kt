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
    const val START = "com.example.maghrib_silent.START"
    const val END = "com.example.maghrib_silent.END"
    const val TEST_END = "com.example.maghrib_silent.TEST_END"
    private const val HALF_HOUR = 30 * 60 * 1000L
    private const val START_ID = 1001
    private const val END_ID = 1002
    private const val TEST_END_ID = 1003

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
        val raw = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
            .getString("times", "[]") ?: "[]"
        val json = JSONArray(raw)
        return (0 until json.length()).map { json.getLong(it) }
    }

    private fun exactAlarmsAllowed(context: Context): Boolean {
        val alarm = context.getSystemService(AlarmManager::class.java)
        return Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms()
    }

    fun arm(context: Context) {
        val prefs = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        val alarm = context.getSystemService(AlarmManager::class.java)
        alarm.cancel(pending(context, START, START_ID))
        alarm.cancel(pending(context, END, END_ID))
        if (!exactAlarmsAllowed(context)) return
        val now = System.currentTimeMillis()

        if (prefs.getBoolean("active", false)) {
            val endAt = prefs.getLong("activeEnd", 0L)
            if (endAt > now) {
                alarm.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP, endAt, pending(context, END, END_ID)
                )
            } else {
                onEnd(context)
            }
            return
        }

        val queue = times(context)
        var index = prefs.getInt("index", 0)
        while (index < queue.size && queue[index] + HALF_HOUR <= now) index++
        prefs.edit().putInt("index", index).apply()
        if (index >= queue.size) return

        val startAt = queue[index]
        if (startAt > now) {
            alarm.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP, startAt, pending(context, START, START_ID)
            )
        } else {
            // If the device was asleep or the app was force-stopped across Maghrib,
            // do not start a stale silent period.
            return
        }
        alarm.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP, startAt + HALF_HOUR, pending(context, END, END_ID)
        )
    }

    private fun saveAndEnableDnd(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        val nm = context.getSystemService(NotificationManager::class.java)
        val audio = context.getSystemService(AudioManager::class.java)
        if (!nm.isNotificationPolicyAccessGranted) return false

        // Snapshot both states before touching either one. commit() is intentional:
        // a receiver can be killed immediately after returning.
        prefs.edit()
            .putInt("previousRinger", audio.ringerMode)
            .putInt("previousFilter", nm.currentInterruptionFilter)
            .putBoolean("active", true)
            .commit()

        return try {
            nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE)
            true
        } catch (_: SecurityException) {
            false
        } catch (_: RuntimeException) {
            false
        }
    }

    private fun restoreSavedState(context: Context, keyPrefix: String = "") {
        val prefs = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        val nm = context.getSystemService(NotificationManager::class.java)
        val audio = context.getSystemService(AudioManager::class.java)
        val filter = prefs.getInt(keyPrefix + "previousFilter", NotificationManager.INTERRUPTION_FILTER_ALL)
        val ringer = prefs.getInt(keyPrefix + "previousRinger", AudioManager.RINGER_MODE_NORMAL)

        // Restore independently. On some Android 10/OEM builds one API may throw;
        // that must never prevent attempting the other restore or clearing state.
        if (nm.isNotificationPolicyAccessGranted) {
            try {
                nm.setInterruptionFilter(filter)
            } catch (_: SecurityException) {
            } catch (_: RuntimeException) {
            }
        }
        try {
            audio.ringerMode = ringer
        } catch (_: SecurityException) {
        } catch (_: RuntimeException) {
        }
    }

    fun onStart(context: Context) {
        val prefs = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        if (prefs.getBoolean("active", false)) return
        val queue = times(context)
        val index = prefs.getInt("index", 0)
        if (index >= queue.size) return
        val endAt = queue[index] + HALF_HOUR
        prefs.edit().putLong("activeEnd", endAt).commit()
        saveAndEnableDnd(context)
        arm(context)
    }

    fun onEnd(context: Context) {
        val prefs = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        if (prefs.getBoolean("active", false)) {
            restoreSavedState(context)
            prefs.edit().putBoolean("active", false).remove("activeEnd").commit()
        }
        // Advance only once; duplicate END broadcasts cannot skip a future day.
        val queue = times(context)
        val index = prefs.getInt("index", 0)
        if (index < queue.size && queue[index] + HALF_HOUR <= System.currentTimeMillis()) {
            prefs.edit().putInt("index", index + 1).commit()
        }
        arm(context)
    }

    fun testNow(context: Context): Boolean {
        val nm = context.getSystemService(NotificationManager::class.java)
        if (!nm.isNotificationPolicyAccessGranted) return false
        val prefs = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        if (prefs.getBoolean("testActive", false)) return false
        val audio = context.getSystemService(AudioManager::class.java)
        prefs.edit()
            .putInt("testPreviousRinger", audio.ringerMode)
            .putInt("testPreviousFilter", nm.currentInterruptionFilter)
            .putBoolean("testActive", true)
            .commit()
        try {
            nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE)
        } catch (_: Exception) {
            prefs.edit().putBoolean("testActive", false).commit()
            return false
        }
        val alarm = context.getSystemService(AlarmManager::class.java)
        val end = System.currentTimeMillis() + 30_000L
        alarm.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP, end, pending(context, TEST_END, TEST_END_ID)
        )
        return true
    }

    fun endTest(context: Context) {
        val prefs = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("testActive", false)) return
        restoreSavedState(context, "test")
        prefs.edit().putBoolean("testActive", false).commit()
    }
}
