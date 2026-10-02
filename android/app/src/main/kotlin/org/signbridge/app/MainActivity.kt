package org.signbridge.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "org.signbridge.app/share"
    private var channel: MethodChannel? = null
    private var pendingSharedText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedText" -> { result.success(pendingSharedText); pendingSharedText = null }
                else -> result.notImplemented()
            }
        }
        captureShare(intent, notifyFlutter = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureShare(intent, notifyFlutter = true)
    }

    private fun captureShare(intent: Intent?, notifyFlutter: Boolean) {
        if (intent?.action != Intent.ACTION_SEND || intent.type != "text/plain") return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        if (text.isBlank()) return
        if (notifyFlutter) channel?.invokeMethod("sharedText", text) else pendingSharedText = text
    }
}
