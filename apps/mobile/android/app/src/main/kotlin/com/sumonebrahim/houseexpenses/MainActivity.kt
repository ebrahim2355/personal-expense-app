package com.sumonebrahim.houseexpenses

import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the one platform channel this app owns: Android's power-management
 * stance toward background sync.
 *
 * The Dart side is `lib/src/background/background_work_policy.dart`. Because the
 * channel lives on the Activity, only the UI isolate can reach it — the
 * WorkManager isolate has no handler and does not need one.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isExemptFromBatteryOptimization" ->
                        result.success(isExemptFromBatteryOptimization())
                    "requestBatteryExemption" ->
                        result.success(launch(batteryExemptionIntent()))
                    "openAppSettings" ->
                        result.success(launch(appSettingsIntent()))
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Whether this app sits on the power-save whitelist, which is what exempts
     * its periodic work from Doze and JobScheduler quota. Needs no permission to
     * read, unlike the dialog that changes it.
     */
    private fun isExemptFromBatteryOptimization(): Boolean {
        val power = getSystemService(POWER_SERVICE) as? PowerManager ?: return false
        return power.isIgnoringBatteryOptimizations(packageName)
    }

    // Play restricts this intent to apps whose core function needs it. This app
    // is sideloaded onto two phones and never published, so the restriction does
    // not apply; the alternative would be sending the member hunting through
    // Android Settings for a switch we can name exactly.
    @SuppressLint("BatteryLife")
    private fun batteryExemptionIntent() =
        Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.fromParts("package", packageName, null),
        )

    private fun appSettingsIntent() =
        Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null),
        )

    /**
     * Reports whether the screen actually opened. Some OEM builds ship without
     * these activities, and answering false lets the Dart side say so instead of
     * throwing an exception across the channel at a caller that only wanted to
     * know if a dialog appeared.
     */
    private fun launch(intent: Intent): Boolean =
        try {
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }

    private companion object {
        const val CHANNEL = "com.sumonebrahim.houseexpenses/background-work-policy"
    }
}
