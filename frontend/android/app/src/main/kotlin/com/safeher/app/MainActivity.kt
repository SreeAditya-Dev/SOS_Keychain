package com.safeher.app

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.safeher.app/lifecycle"
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Check if device is paired and start KeepAlive service
        val sharedPrefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val hasPairedDevice = sharedPrefs.contains("flutter.paired_device")
        
        if (hasPairedDevice) {
            KeepAliveService.startService(this)
        }
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "keepAlive" -> {
                    // Keep Flutter engine alive
                    result.success(true)
                }
                "startKeepAliveService" -> {
                    KeepAliveService.startService(this)
                    result.success(true)
                }
                "stopKeepAliveService" -> {
                    KeepAliveService.stopService(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    override fun onDestroy() {
        // Don't stop KeepAlive service when activity is destroyed
        // This keeps BLE running in background
        super.onDestroy()
    }
}
