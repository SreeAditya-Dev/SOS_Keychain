package com.safeher.app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.safeher.app/lifecycle"
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "keepAlive" -> {
                    // Keep Flutter engine alive
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    override fun onDestroy() {
        // Don't destroy Flutter engine when activity is destroyed
        // This keeps BLE running in background
        super.onDestroy()
    }
}
