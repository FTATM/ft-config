package com.example.ftconfig.wifi

import android.content.Context
import android.net.*
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.Q)
class WifiConnector(
    private val context: Context
) {

    private val connectivityManager =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    // NetworkCallback methods aren't guaranteed to run on the main thread unless a
    // Handler is supplied — without this, calling MethodChannel.Result from inside
    // onAvailable/onUnavailable/onLost can crash Flutter ("not on the platform thread").
    private val mainHandler = Handler(Looper.getMainLooper())

    private var callback: ConnectivityManager.NetworkCallback? = null

    fun connect(
        ssid: String,
        password: String,
        onSuccess: () -> Unit,
        onError: (String) -> Unit
    ) {

        disconnect()

        val specifier = WifiNetworkSpecifier.Builder()
            .setSsid(ssid)
            .setWpa2Passphrase(password)
            .build()

        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier)
            .build()

        callback = object : ConnectivityManager.NetworkCallback() {

            override fun onAvailable(network: Network) {
                connectivityManager.bindProcessToNetwork(network)
                onSuccess()
            }

            override fun onUnavailable() {
                onError("Unable to connect")
            }

            override fun onLost(network: Network) {
                disconnect()
            }
        }

        connectivityManager.requestNetwork(request, callback!!, mainHandler)
    }

    /**
     * Returns true if teardown completed without error, false otherwise.
     */
    fun disconnect(): Boolean {

        return try {

            callback?.let {
                try {
                    connectivityManager.unregisterNetworkCallback(it)
                } catch (_: IllegalArgumentException) {
                    // callback was already unregistered — safe to ignore
                }
            }

            callback = null
            connectivityManager.bindProcessToNetwork(null)
            true

        } catch (_: Exception) {
            false
        }
    }
}
