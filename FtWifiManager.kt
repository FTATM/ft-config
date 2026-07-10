package com.example.ftconfig.wifi

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel

/**
 * Renamed from "WifiManager" to avoid colliding with android.net.wifi.WifiManager,
 * which this class needs to reference directly for scan/enable/status operations.
 */
class FtWifiManager(
    private val activity: Activity
) {

    private val permission = WifiPermission(activity)

    private val connector by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            WifiConnector(activity)
        } else {
            null
        }
    }

    private val systemWifiManager: WifiManager
        get() = activity.applicationContext
            .getSystemService(Context.WIFI_SERVICE) as WifiManager

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var isScanning = false

    // ---------------------------------------------------------------------
    // Permissions
    // ---------------------------------------------------------------------

    fun hasPermission(): Boolean = permission.hasPermission()

    fun getPermissions(): Array<String> = permission.getPermissions()

    fun requestPermission() = permission.requestPermission()

    fun handlePermissionResult(requestCode: Int, grantResults: IntArray): Boolean =
        permission.handleResult(requestCode, grantResults)

    // ---------------------------------------------------------------------
    // Scan
    // ---------------------------------------------------------------------

    fun scanWifi(
        onSuccess: (List<Map<String, Any?>>) -> Unit,
        onError: (String) -> Unit
    ) {

        if (!hasPermission()) {
            onError("Missing required location/nearby-wifi permission")
            return
        }

        // Android throttles startScan() (~4 calls per 2 min since API 28). If throttled,
        // startScan() can still return true but the broadcast may never arrive — without
        // a guard here the receiver leaks and the caller hangs forever waiting for a result.
        if (isScanning) {
            onError("Scan already in progress")
            return
        }

        isScanning = true

        val wifiManager = systemWifiManager
        var timeoutRunnable: Runnable? = null
        var finished = false

        fun finish(action: () -> Unit) {
            if (finished) return
            finished = true
            isScanning = false
            timeoutRunnable?.let { mainHandler.removeCallbacks(it) }
            action()
        }

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {

                try {
                    activity.unregisterReceiver(this)
                } catch (_: IllegalArgumentException) {
                    // already unregistered
                }

                val updated = intent.getBooleanExtra(
                    WifiManager.EXTRA_RESULTS_UPDATED,
                    false
                )

                if (!updated) {
                    finish { onError("Scan failed") }
                    return
                }

                try {
                    val results = wifiManager.scanResults.map { scanResult ->
                        mapOf(
                            "ssid" to scanResult.SSID,
                            "bssid" to scanResult.BSSID,
                            "level" to scanResult.level,
                            "frequency" to scanResult.frequency
                        )
                    }
                    finish { onSuccess(results) }
                } catch (_: SecurityException) {
                    finish { onError("Missing permission to read scan results") }
                }
            }
        }

        // Safety net: if the broadcast never fires (throttled or otherwise), unregister
        // the receiver and report a timeout instead of hanging indefinitely.
        timeoutRunnable = Runnable {
            try {
                activity.unregisterReceiver(receiver)
            } catch (_: IllegalArgumentException) {
            }
            finish { onError("Scan timed out — Android may be throttling scan requests") }
        }
        mainHandler.postDelayed(timeoutRunnable, 10_000L)

        val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            activity.registerReceiver(receiver, filter)
        }

        val started = wifiManager.startScan()

        if (!started) {
            try {
                activity.unregisterReceiver(receiver)
            } catch (_: IllegalArgumentException) {
            }
            finish { onError("Unable to start scan") }
        }
    }

    // ---------------------------------------------------------------------
    // Current connection info
    // ---------------------------------------------------------------------

    fun getCurrentWifi(): String? {

        if (!hasPermission()) return null

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {

            val connectivityManager = activity.getSystemService(
                Context.CONNECTIVITY_SERVICE
            ) as ConnectivityManager

            val network = connectivityManager.activeNetwork ?: return null
            val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return null
            val transportInfo = capabilities.transportInfo

            (transportInfo as? WifiInfo)?.ssid?.trim('"')

        } else {
            @Suppress("DEPRECATION")
            systemWifiManager.connectionInfo?.ssid?.trim('"')
        }
    }

    // ---------------------------------------------------------------------
    // Wi-Fi radio state
    // ---------------------------------------------------------------------

    fun isWifiEnabled(): Boolean = systemWifiManager.isWifiEnabled

    /**
     * On Android 10+ (Q), apps can no longer toggle Wi-Fi directly — this opens the
     * system Wi-Fi settings panel instead and returns the current (pre-toggle) state.
     */
    fun enableWifi(): Boolean {

        val wifiManager = systemWifiManager

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val panelIntent = Intent(Settings.Panel.ACTION_WIFI)
            panelIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(panelIntent)
            wifiManager.isWifiEnabled
        } else {
            @Suppress("DEPRECATION")
            wifiManager.isWifiEnabled = true
            wifiManager.isWifiEnabled
        }
    }

    // ---------------------------------------------------------------------
    // Connect / disconnect (delegates to WifiConnector on Q+)
    // ---------------------------------------------------------------------

    fun connect(
        ssid: String,
        password: String,
        result: MethodChannel.Result
    ) {

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("UNSUPPORTED", "Android 10+ required", null)
            return
        }

        if (!hasPermission()) {
            result.error("PERMISSION_DENIED", "Missing required permissions", null)
            return
        }

        connector!!.connect(
            ssid,
            password,
            onSuccess = {
                activity.runOnUiThread { result.success(true) }
            },
            onError = { msg ->
                activity.runOnUiThread { result.error("CONNECT_ERROR", msg, null) }
            }
        )
    }

    fun disconnect(): Boolean {

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return false
        }

        return connector?.disconnect() ?: false
    }
}
