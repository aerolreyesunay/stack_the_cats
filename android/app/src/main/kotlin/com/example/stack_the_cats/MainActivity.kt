package com.example.stack_the_cats

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import com.facebook.FacebookSdk
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Starts the Facebook SDK, which doesn't start on its own (see
        // AutoInitEnabled in AndroidManifest.xml), just before Facebook
        // sign-in.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stack_the_cats/facebook")
            .setMethodCallHandler { call, result ->
                if (call.method != "start") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // Just for this launch: it still won't start by itself next time.
                FacebookSdk.fullyInitialize()
                result.success(true)
            }
        // Opens a web page in the browser (Settings: privacy policy and
        // account deletion). Answers true if a browser opened it.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stack_the_cats/links")
            .setMethodCallHandler { call, result ->
                if (call.method != "open") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val url = call.arguments as? String
                if (url == null || !url.startsWith("https://")) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                    result.success(true)
                } catch (e: ActivityNotFoundException) {
                    result.success(false)
                }
            }
    }
}
