package com.example.maghrib_silent

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class PrayerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            "com.example.maghrib_silent.START" -> PrayerScheduler.onStart(context)
            "com.example.maghrib_silent.END" -> PrayerScheduler.onEnd(context)
        }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        PrayerScheduler.arm(context)
    }
}
