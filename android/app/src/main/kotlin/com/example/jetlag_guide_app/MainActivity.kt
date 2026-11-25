package com.example.jetlag_guide_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialLink" -> result.success(scheduleLink(intent))
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = scheduleLink(intent) ?: return
        channel?.invokeMethod("onLink", link)
    }

    private fun scheduleLink(source: Intent?): String? {
        val data = source?.data ?: return null
        if (data.scheme != "jetlagguide") return null
        return data.toString()
    }

    companion object {
        private const val CHANNEL = "jetlag_guide/deep_link"
    }
}
