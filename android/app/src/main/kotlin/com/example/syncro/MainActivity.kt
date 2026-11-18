package com.example.syncro

import android.Manifest
import android.accounts.Account
import android.accounts.AccountManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val SYNC_CHANNEL = "com.example.syncro/google_calendar_sync"
        private const val CALENDAR_SCOPE = "oauth2:https://www.googleapis.com/auth/calendar"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYNC_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestCalendarSync" -> {
                        val email = call.argument<String>("email")
                        requestNativeCalendarSync(email)
                        result.success(true)
                    }
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            if (ContextCompat.checkSelfPermission(
                                    this,
                                    Manifest.permission.POST_NOTIFICATIONS
                                ) != PackageManager.PERMISSION_GRANTED
                            ) {
                                ActivityCompat.requestPermissions(
                                    this,
                                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                    1002
                                )
                            }
                        }
                        result.success(true)
                    }
                    "showLocalNotification" -> {
                        val id = call.argument<Int>("id") ?: 101
                        val title = call.argument<String>("title") ?: "Syncro Alert"
                        val body = call.argument<String>("body") ?: ""
                        showNativeNotification(id, title, body)
                        result.success(true)
                    }
                    "acquireAccountToken" -> {
                        val email = call.argument<String>("email")
                        if (email.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "Google account email is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            AccountManager.get(this).getAuthToken(
                                Account(email, "com.google"),
                                CALENDAR_SCOPE,
                                null,
                                this,
                                { future ->
                                    try {
                                        val bundle = future.result
                                        val token = bundle.getString(AccountManager.KEY_AUTHTOKEN)
                                        runOnUiThread {
                                            if (!token.isNullOrEmpty()) {
                                                result.success(token)
                                            } else {
                                                result.error(
                                                    "NO_TOKEN",
                                                    "No auth token returned for $email",
                                                    null
                                                )
                                            }
                                        }
                                    } catch (e: Exception) {
                                        runOnUiThread {
                                            result.error(
                                                "AUTH_ERROR",
                                                e.message ?: "Failed to acquire account token",
                                                null
                                            )
                                        }
                                    }
                                },
                                null
                            )
                        } catch (e: Exception) {
                            result.error(
                                "AUTH_ERROR",
                                e.message ?: "AccountManager failed to start token request",
                                null
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun enableVisibilityAndSyncForGoogleCalendars() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_CALENDAR) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        try {
            val values = ContentValues().apply {
                put(CalendarContract.Calendars.VISIBLE, 1)
                put(CalendarContract.Calendars.SYNC_EVENTS, 1)
            }
            contentResolver.update(
                CalendarContract.Calendars.CONTENT_URI,
                values,
                "${CalendarContract.Calendars.ACCOUNT_TYPE} = ? AND (${CalendarContract.Calendars.VISIBLE} = 0 OR ${CalendarContract.Calendars.SYNC_EVENTS} = 0)",
                arrayOf("com.google")
            )
        } catch (_: Exception) {
        }
    }

    private fun requestNativeCalendarSync(email: String?) {
        enableVisibilityAndSyncForGoogleCalendars()

        val extras = Bundle().apply {
            putBoolean(ContentResolver.SYNC_EXTRAS_MANUAL, true)
            putBoolean(ContentResolver.SYNC_EXTRAS_EXPEDITED, true)
        }
        val accounts = linkedSetOf<Account>()
        if (!email.isNullOrBlank() && email.contains("@")) {
            accounts.add(Account(email.trim(), "com.google"))
        }

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALENDAR) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            try {
                contentResolver.query(
                    CalendarContract.Calendars.CONTENT_URI,
                    arrayOf(CalendarContract.Calendars.ACCOUNT_NAME),
                    "${CalendarContract.Calendars.ACCOUNT_TYPE} = ?",
                    arrayOf("com.google"),
                    null
                )?.use { cursor ->
                    while (cursor.moveToNext()) {
                        val acctName = cursor.getString(0)
                        if (!acctName.isNullOrBlank()) {
                            accounts.add(Account(acctName, "com.google"))
                        }
                    }
                }
            } catch (_: Exception) {
            }
        }

        if (accounts.isEmpty()) {
            ContentResolver.requestSync(null, CalendarContract.AUTHORITY, extras)
        } else {
            for (account in accounts) {
                ContentResolver.requestSync(account, CalendarContract.AUTHORITY, extras)
            }
        }

        Handler(Looper.getMainLooper()).postDelayed({
            enableVisibilityAndSyncForGoogleCalendars()
        }, 2500L)
    }

    private fun showNativeNotification(id: Int, title: String, body: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "syncro_smart_alerts"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Syncro Smart Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Reminders and calendar conflict alerts"
            }
            manager.createNotificationChannel(channel)
        }
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
        manager.notify(id, notification)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableHighRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        enableHighRefreshRate()
    }

    private fun enableHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            } ?: return

            val supportedModes = currentDisplay.supportedModes
            if (supportedModes.isNullOrEmpty()) return

            val activeMode = currentDisplay.mode
            // Pick the mode matching current resolution with the highest refresh rate (e.g. 120Hz)
            val highestRefreshMode = supportedModes
                .filter {
                    it.physicalWidth == activeMode.physicalWidth &&
                        it.physicalHeight == activeMode.physicalHeight
                }
                .maxByOrNull { it.refreshRate }
                ?: supportedModes.maxByOrNull { it.refreshRate }
                ?: return

            val layoutParams = window.attributes
            if (layoutParams.preferredDisplayModeId != highestRefreshMode.modeId ||
                layoutParams.preferredRefreshRate != highestRefreshMode.refreshRate
            ) {
                layoutParams.preferredDisplayModeId = highestRefreshMode.modeId
                layoutParams.preferredRefreshRate = highestRefreshMode.refreshRate
                window.attributes = layoutParams
            }
        }
    }
}
