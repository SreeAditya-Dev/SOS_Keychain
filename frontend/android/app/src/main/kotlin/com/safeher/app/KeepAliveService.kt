package com.safeher.app

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Native Android Service that keeps the Flutter engine alive
 * even when the app is swiped away from Recent Apps.
 * 
 * This service:
 * 1. Runs as a foreground service (can't be killed easily)
 * 2. Holds a partial WakeLock to keep CPU alive
 * 3. Maintains Flutter engine to keep BLE callbacks working
 * 4. Restarts automatically if killed
 */
class KeepAliveService : Service() {
    private var flutterEngine: FlutterEngine? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val NOTIFICATION_ID = 12345
    private val CHANNEL_ID = "safeher_keepalive"
    
    companion object {
        private const val ACTION_START = "com.safeher.app.START_KEEPALIVE"
        private const val ACTION_STOP = "com.safeher.app.STOP_KEEPALIVE"
        
        fun startService(context: Context) {
            val intent = Intent(context, KeepAliveService::class.java).apply {
                action = ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stopService(context: Context) {
            val intent = Intent(context, KeepAliveService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        
        // Create notification channel
        createNotificationChannel()
        
        // Acquire partial WakeLock to keep CPU alive
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "SafeHer::KeepAliveWakeLock"
        ).apply {
            acquire()
        }
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                // Start as foreground service
                val notification = createNotification()
                startForeground(NOTIFICATION_ID, notification)
                
                // Initialize Flutter engine if not already running
                initFlutterEngine()
            }
            ACTION_STOP -> {
                stopSelf()
            }
        }
        
        // Restart service if killed
        return START_STICKY
    }
    
    override fun onTaskRemoved(rootIntent: Intent?) {
        // Called when app is swiped away from Recent Apps
        // Restart the service to keep it alive
        val restartIntent = Intent(applicationContext, KeepAliveService::class.java).apply {
            action = ACTION_START
        }
        
        val pendingIntent = PendingIntent.getService(
            this,
            1,
            restartIntent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.set(
            AlarmManager.RTC_WAKEUP,
            System.currentTimeMillis() + 1000,
            pendingIntent
        )
        
        super.onTaskRemoved(rootIntent)
    }
    
    override fun onDestroy() {
        // Release WakeLock
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        
        // Clean up Flutter engine
        flutterEngine?.destroy()
        flutterEngine = null
        
        // Schedule restart
        scheduleRestart()
        
        super.onDestroy()
    }
    
    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "SafeHer Protection Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps SafeHer running in the background for your safety"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SafeHer Active")
            .setContentText("Your SOS keychain is protected and monitoring")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
    
    private fun initFlutterEngine() {
        if (flutterEngine == null) {
            // Keep Flutter engine alive in background
            flutterEngine = FlutterEngine(this)
            
            // This ensures BLE callbacks continue to work
            // The Flutter app will connect to this engine
        }
    }
    
    private fun scheduleRestart() {
        // Schedule service restart if it gets killed
        val restartIntent = Intent(applicationContext, KeepAliveService::class.java).apply {
            action = ACTION_START
        }
        
        val pendingIntent = PendingIntent.getService(
            this,
            1,
            restartIntent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.set(
            AlarmManager.RTC_WAKEUP,
            System.currentTimeMillis() + 2000,
            pendingIntent
        )
    }
}
