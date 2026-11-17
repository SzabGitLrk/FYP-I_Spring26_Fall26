package com.example.university_point_locator

import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val batteryChannel = "com.example.university_point_locator/battery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, batteryChannel)
            .setMethodCallHandler { call, result ->
                val power = getSystemService(POWER_SERVICE) as PowerManager
                when (call.method) {
                    // Is this app already on Android's battery-optimisation
                    // allowlist (i.e. Doze/OEM killers leave it alone)?
                    "isIgnoringBatteryOptimizations" ->
                        result.success(power.isIgnoringBatteryOptimizations(packageName))

                    // Ask for the exemption. The direct dialog needs
                    // REQUEST_IGNORE_BATTERY_OPTIMIZATIONS and some OEM skins
                    // refuse it outright, so fall back to the allowlist
                    // settings screen where the driver whitelists the app by
                    // hand. Either way the Dart side re-checks on resume.
                    "requestIgnoreBatteryOptimizations" -> {
                        if (power.isIgnoringBatteryOptimizations(packageName)) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                )
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                startActivity(
                                    Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                )
                                result.success(true)
                            } catch (e2: Exception) {
                                // Device offered neither path (no dialog here).
                                result.success(false)
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
