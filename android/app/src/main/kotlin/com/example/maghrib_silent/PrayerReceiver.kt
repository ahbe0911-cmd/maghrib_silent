package com.example.maghrib_silent

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class PrayerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            PrayerScheduler.START -> PrayerScheduler.onStart(context)
            PrayerScheduler.END -> PrayerScheduler.onEnd(context)
            PrayerScheduler.TEST_END -> PrayerScheduler.endTest(context)
        }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        PrayerScheduler.arm(context)
    }
}
