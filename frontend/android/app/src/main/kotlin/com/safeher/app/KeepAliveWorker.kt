package com.safeher.app

import android.content.Context
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
    
    override fun doWork(): Result {
        // Check if service should be running (device is paired)
        val sharedPrefs = applicationContext.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE
        )
        
        val hasPairedDevice = sharedPrefs.contains("flutter.paired_device")
        
        if (hasPairedDevice) {
            // Restart the KeepAliveService
            KeepAliveService.startService(applicationContext)
        }
        
        return Result.success()
    }
}
