package com.livinlabs.scansheet

import android.content.Intent
import android.os.SystemClock
import android.provider.Settings
import java.security.MessageDigest
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "scansheet/launch"
        private const val DEVICE_CHANNEL = "scansheet/device"
        private const val EXTRA_ACTION = "launch_action"
    }

    private var launchChannel: MethodChannel? = null
    private var pendingAction: String? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        pendingAction = intent?.getStringExtra(EXTRA_ACTION)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launchChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        launchChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialAction") {
                val action = pendingAction ?: intent?.getStringExtra(EXTRA_ACTION)
                pendingAction = null
                intent?.removeExtra(EXTRA_ACTION)
                result.success(action)
            } else {
                result.notImplemented()
            }
        }
        // Free-plan usage (lib/core/services/device_service.dart): a stable
        // id for this phone and app, and the clock since boot.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deviceId" -> result.success(deviceId())
                    "elapsedRealtime" -> result.success(SystemClock.elapsedRealtime())
                    else -> result.notImplemented()
                }
            }
    }

    /** ANDROID_ID survives reinstalls and cleared data; only a hash leaves the phone. */
    private fun deviceId(): String? {
        val raw = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
            ?: return null
        val digest = MessageDigest.getInstance("SHA-256")
            .digest("scansheet:$raw".toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = intent.getStringExtra(EXTRA_ACTION) ?: return
        pendingAction = action
        launchChannel?.invokeMethod("action", action, object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (pendingAction == action) pendingAction = null
                if (this@MainActivity.intent?.getStringExtra(EXTRA_ACTION) == action) {
                    this@MainActivity.intent?.removeExtra(EXTRA_ACTION)
                }
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

            override fun notImplemented() = Unit
        })
    }
}
