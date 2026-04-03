package com.safeher.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Receives boot completed, package replaced, and custom restart broadcasts.
 * Restarts the KeepAliveService to ensure protection after device reboot.
 */
class BootReceiver : BroadcastReceiver() {
    private val TAG = "SafeHer.BootReceiver"
    
    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Received action: ${intent.action}")
        
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.safeher.app.RESTART_SERVICE" -> {
                Log.d(TAG, "Triggering service restart")
                restartServiceIfNeeded(context)
            }
        }
    }
    
    private fun restartServiceIfNeeded(context: Context) {
        try {
            // Check if device is paired
            val sharedPrefs = context.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE
            )
            
            val hasPairedDevice = sharedPrefs.contains("flutter.paired_device")
            
            if (hasPairedDevice) {
                Log.d(TAG, "Paired device found, starting KeepAlive service")
                KeepAliveService.startService(context)
                KeepAliveService.schedulePeriodicWork(context)
            } else {
                Log.d(TAG, "No paired device, skipping service start")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error restarting service: ${e.message}")
        }
    }
}
