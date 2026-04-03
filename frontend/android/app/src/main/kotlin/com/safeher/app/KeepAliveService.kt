package com.safeher.app

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.*
import java.util.concurrent.TimeUnit

/**
 * Native Android Service that keeps the Flutter engine alive
 * even when the app is swiped away from Recent Apps.
 * 
 * This service:
 * 1. Runs as a foreground service (can't be killed easily)
 * 2. Holds a partial WakeLock to keep CPU alive
 * 3. Launches the Flutter app if killed to restore BLE connections
 * 4. Restarts automatically if killed using multiple mechanisms
 */
class KeepAliveService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private val NOTIFICATION_ID = 12345
    private val CHANNEL_ID = "safeher_keepalive"
    private val TAG = "KeepAliveService"
    
    companion object {
        private const val ACTION_START = "com.safeher.app.START_KEEPALIVE"
        private const val ACTION_STOP = "com.safeher.app.STOP_KEEPALIVE"
        
        @Volatile
        private var isRunning = false
        
        fun isServiceRunning(): Boolean = isRunning
        
        fun startService(context: Context) {
            val intent = Intent(context, KeepAliveService::class.java).apply {
                action = ACTION_START
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.e("KeepAliveService", "Failed to start service: ${e.message}")
            }
        }
        
        fun stopService(context: Context) {
            val intent = Intent(context, KeepAliveService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
        
        fun schedulePeriodicWork(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiresBatteryNotLow(false)
                .setRequiresCharging(false)
                .build()
            
            val keepAliveRequest = PeriodicWorkRequestBuilder<KeepAliveWorker>(
                15, TimeUnit.MINUTES,  // Minimum interval
                5, TimeUnit.MINUTES    // Flex interval
            )
                .setConstraints(constraints)
                .addTag("safeher_keepalive")
                .build()
            
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                "safeher_keepalive_work",
                ExistingPeriodicWorkPolicy.KEEP,
                keepAliveRequest
            )
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service onCreate")
        
        // Create notification channel
        createNotificationChannel()
        
        // Acquire partial WakeLock to keep CPU alive
        acquireWakeLock()
        
        isRunning = true
    }
    
    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "SafeHer::KeepAliveWakeLock"
            ).apply {
                // Set timeout to prevent battery drain if something goes wrong
                acquire(10 * 60 * 1000L) // 10 minutes timeout, will be renewed
            }
            Log.d(TAG, "WakeLock acquired")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire WakeLock: ${e.message}")
        }
    }
    
    private fun renewWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        acquireWakeLock()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: ${intent?.action}")
        
        when (intent?.action) {
            ACTION_START -> {
                // Start as foreground service
                val notification = createNotification()
                startForeground(NOTIFICATION_ID, notification)
                
                // Renew WakeLock
                renewWakeLock()
                
                // Launch Flutter app if not running
                launchFlutterAppIfNeeded()
                
                // Schedule periodic work as backup
                schedulePeriodicWork(this)
            }
            ACTION_STOP -> {
                isRunning = false
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
        }
        
        // Restart service if killed - use START_REDELIVER_INTENT for more reliability
        return START_STICKY
    }
    
    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.d(TAG, "onTaskRemoved - app swiped away")
        
        // Called when app is swiped away from Recent Apps
        // Multiple restart mechanisms for reliability
        
        // 1. Schedule immediate restart via AlarmManager
        scheduleAlarmRestart(1000)
        
        // 2. Send broadcast to BootReceiver
        val restartBroadcast = Intent(this, BootReceiver::class.java).apply {
            action = "com.safeher.app.RESTART_SERVICE"
        }
        sendBroadcast(restartBroadcast)
        
        // 3. Re-enqueue WorkManager task
        schedulePeriodicWork(this)
        
        super.onTaskRemoved(rootIntent)
    }
    
    override fun onDestroy() {
        Log.d(TAG, "Service onDestroy")
        isRunning = false
        
        // Release WakeLock
        releaseWakeLock()
        
        // Schedule restart
        scheduleAlarmRestart(2000)
        
        super.onDestroy()
    }
    
    private fun releaseWakeLock() {
        try {
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                    Log.d(TAG, "WakeLock released")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to release WakeLock: ${e.message}")
        }
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
                enableLights(false)
                enableVibration(false)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SafeHer Active")
            .setContentText("Your SOS keychain is protected and monitoring")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }
    
    private fun launchFlutterAppIfNeeded() {
        // Check if the Flutter activity is running
        // If not, launch it in background mode
        try {
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val runningTasks = activityManager.appTasks
            
            var isAppRunning = false
            for (task in runningTasks) {
                val info = task.taskInfo
                if (info.baseActivity?.packageName == packageName) {
                    isAppRunning = true
                    break
                }
            }
            
            if (!isAppRunning) {
                Log.d(TAG, "Flutter app not running, launching...")
                val launchIntent = Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                            Intent.FLAG_ACTIVITY_CLEAR_TOP
                    putExtra("from_background", true)
                }
                startActivity(launchIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking/launching app: ${e.message}")
        }
    }
    
    private fun scheduleAlarmRestart(delayMs: Long) {
        try {
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
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    System.currentTimeMillis() + delayMs,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    System.currentTimeMillis() + delayMs,
                    pendingIntent
                )
            }
            Log.d(TAG, "Scheduled alarm restart in ${delayMs}ms")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to schedule alarm restart: ${e.message}")
        }
    }
}
