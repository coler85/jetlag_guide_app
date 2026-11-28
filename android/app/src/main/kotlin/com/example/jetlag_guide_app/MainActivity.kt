package com.example.jetlag_guide_app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.AlarmClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var deepLinkChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deepLinkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEEP_LINK_CHANNEL,
        ).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialLink" -> result.success(scheduleLink(intent))
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CLOCK_ALARM_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAlarm" -> setAlarm(call.arguments, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = scheduleLink(intent) ?: return
        deepLinkChannel?.invokeMethod("onLink", link)
    }

    private fun setAlarm(arguments: Any?, result: MethodChannel.Result) {
        val args = arguments as? Map<*, *>
        val hour = intArg(args?.get("hour"))
        val minutes = intArg(args?.get("minutes"))
        val message = args?.get("message") as? String
        if (hour == null || minutes == null || message == null) {
            result.error("bad_args", "hour, minutes, message required", null)
            return
        }
        try {
            val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(AlarmClock.EXTRA_HOUR, hour)
                putExtra(AlarmClock.EXTRA_MINUTES, minutes)
                putExtra(AlarmClock.EXTRA_MESSAGE, message)
                putExtra(AlarmClock.EXTRA_SKIP_UI, false)
            }
            startActivity(intent)
            result.success(null)
        } catch (error: ActivityNotFoundException) {
            result.error("no_clock", error.message, null)
        }
    }

    private fun intArg(value: Any?): Int? = when (value) {
        is Int -> value
        is Long -> value.toInt()
        is Number -> value.toInt()
        else -> null
    }

    private fun scheduleLink(source: Intent?): String? {
        val data = source?.data ?: return null
        if (data.scheme != "jetlagguide") return null
        return data.toString()
    }

    companion object {
        private const val DEEP_LINK_CHANNEL = "jetlag_guide/deep_link"
        private const val CLOCK_ALARM_CHANNEL = "jetlag_guide/clock_alarm"
    }
}
