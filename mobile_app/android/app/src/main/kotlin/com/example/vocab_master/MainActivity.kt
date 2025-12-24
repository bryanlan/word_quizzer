package com.example.vocab_master

import android.content.Context
import android.os.UserManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.vocab_master/user"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getUserName") {
                    result.success(fetchUserName())
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun fetchUserName(): String? {
        val userManager = getSystemService(Context.USER_SERVICE) as? UserManager
        val name = userManager?.userName?.trim()
        return if (name.isNullOrBlank()) null else name
    }
}
