package com.flappyspikes.flappy_spikes

import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Play pre-launch reports and Firebase Test Lab run on devices that
        // set this system setting; AdMobRewardedAds never loads ads there
        // (robot taps on real ads count as invalid traffic).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flappy_spikes/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTestLab" -> result.success(
                        Settings.System.getString(contentResolver, "firebase.test.lab") == "true"
                    )
                    else -> result.notImplemented()
                }
            }
    }
}
