package jp.aile.nanikiru_cam

import android.content.Context
import android.os.Build
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // ライブナビの温度警告（設計書 3.3）。lib/live/live_device.dart と同じ名前。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, THERMAL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getThermalState" -> result.success(thermalState())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * `status`: PowerManager.currentThermalStatus（API 29+、0=NONE … 3=SEVERE … 6=SHUTDOWN）。
     * `headroom`: PowerManager.getThermalHeadroom(10)（API 30+、1.0 で SEVERE 相当。
     * 取れない・呼び過ぎで NaN のときは null）。
     * `moderateHeadroom` / `severeHeadroom`: 端末自身の headroom のしきい値
     *（API 35+ の getThermalHeadroomThresholds。端末ごとに違うので固定値より正確。無ければ null）。
     */
    private fun thermalState(): Map<String, Any?> {
        val power = getSystemService(Context.POWER_SERVICE) as? PowerManager
        var status: Int? = null
        var headroom: Double? = null
        var moderate: Double? = null
        var severe: Double? = null
        if (power != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            status = power.currentThermalStatus
        }
        if (power != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val value = power.getThermalHeadroom(10)
            if (!value.isNaN()) headroom = value.toDouble()
        }
        if (power != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            try {
                val thresholds = power.thermalHeadroomThresholds
                moderate = thresholds[PowerManager.THERMAL_STATUS_MODERATE]
                    ?.takeIf { !it.isNaN() }?.toDouble()
                severe = thresholds[PowerManager.THERMAL_STATUS_SEVERE]
                    ?.takeIf { !it.isNaN() }?.toDouble()
            } catch (_: Exception) {
                // HAL が対応していない端末では固定のしきい値を使う。
            }
        }
        return mapOf(
            "platform" to "android",
            "status" to status,
            "headroom" to headroom,
            "moderateHeadroom" to moderate,
            "severeHeadroom" to severe,
        )
    }

    companion object {
        private const val THERMAL_CHANNEL = "jp.aile.nanikiru_cam/device_thermal"
    }
}
