package com.safeher.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Receives boot completed and package replaced broadcasts.
 * Restarts the KeepAliveService to ensure protection after device reboot.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.d("SafeHer", "Boot/Update received - restarting KeepAlive service")
                
                // Check if device is paired
                val sharedPrefs = context.getSharedPreferences(
                    "FlutterSharedPreferences",
                    Context.MODE_PRIVATE
                )
                
                val hasPairedDevice = sharedPrefs.contains("flutter.paired_device")
                
                if (hasPairedDevice) {
                    KeepAliveService.startService(context)
                }
            }
        }
    }
}
