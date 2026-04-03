package com.safeher.app

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * WorkManager Worker that ensures the KeepAliveService is running.
 * This runs periodically (every 15 minutes minimum) even if app is killed.
 * 
 * Android's JobScheduler/WorkManager survives app death and can restart services.
 */
class KeepAliveWorker(
    context: Context,
    params: WorkerParameters
) : Worker(context, params) {
    
    private val TAG = "KeepAliveWorker"
    
    override fun doWork(): Result {
        Log.d(TAG, "KeepAliveWorker executing")
        
        try {
            // Check if service should be running (device is paired)
            val sharedPrefs = applicationContext.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE
            )
            
            val hasPairedDevice = sharedPrefs.contains("flutter.paired_device")
            
            if (hasPairedDevice) {
                Log.d(TAG, "Device is paired, checking service status")
                
                // Always try to start/restart the service
                if (!KeepAliveService.isServiceRunning()) {
                    Log.d(TAG, "Service not running, starting...")
                    KeepAliveService.startService(applicationContext)
                } else {
                    Log.d(TAG, "Service already running")
                }
                
                // Also try to launch the Flutter app if it's not running
                // This ensures BLE connections are maintained
                launchAppIfNeeded()
            } else {
                Log.d(TAG, "No paired device, skipping")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in KeepAliveWorker: ${e.message}")
            return Result.retry()
        }
        
        return Result.success()
    }
    
    private fun launchAppIfNeeded() {
        try {
            val launchIntent = Intent(applicationContext, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("from_background", true)
            }
            applicationContext.startActivity(launchIntent)
            Log.d(TAG, "Launched Flutter app from worker")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch app: ${e.message}")
        }
    }
}
