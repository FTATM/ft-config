package com.example.ftconfig

import android.os.Bundle
import com.example.ftconfig.wifi.FtWifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "ftconfig/wifi"
    }

    private lateinit var wifiManager: FtWifiManager

    // Holds the Flutter Result for a pending "requestPermission" call so it can be
    // answered once onRequestPermissionsResult fires.
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        wifiManager = FtWifiManager(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                // ==============================
                // Permissions
                // ==============================
                "hasPermission" -> {
                    result.success(wifiManager.hasPermission())
                }

                "requestPermission" -> {
                    if (wifiManager.hasPermission()) {
                        result.success(true)
                    } else {
                        pendingPermissionResult = result
                        wifiManager.requestPermission()
                    }
                }

                // ==============================
                // Scan WiFi
                // ==============================
                "scanWifi" -> {

                    wifiManager.scanWifi(
                        onSuccess = { list ->
                            result.success(list)
                        },
                        onError = { error ->
                            result.error("SCAN_ERROR", error, null)
                        }
                    )
                }

                // ==============================
                // Get current connected WiFi
                // ==============================
                "getCurrentWifi" -> {
                    result.success(wifiManager.getCurrentWifi())
                }

                // ==============================
                // Connect WiFi
                // ==============================
                "connectWifi" -> {

                    val ssid = call.argument<String>("ssid")
                    val password = call.argument<String>("password")

                    if (ssid == null || password == null) {
                        result.error("INVALID_ARGUMENT", "SSID or password missing", null)
                        return@setMethodCallHandler
                    }

                    wifiManager.connect(ssid, password, result)
                }

                // ==============================
                // Disconnect WiFi
                // ==============================
                "disconnectWifi" -> {
                    val status = wifiManager.disconnect()
                    result.success(status)
                }

                // ==============================
                // Check WiFi enabled
                // ==============================
                "isWifiEnabled" -> {
                    result.success(wifiManager.isWifiEnabled())
                }

                // ==============================
                // Enable WiFi
                // ==============================
                "enableWifi" -> {
                    result.success(wifiManager.enableWifi())
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        val granted = wifiManager.handlePermissionResult(requestCode, grantResults)

        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }
}
