package com.example.ftconfig.wifi

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class WifiPermission(
    private val activity: Activity
) {

    companion object {

        const val REQUEST_WIFI_PERMISSION = 2001

        fun hasWifiPermission(context: Context): Boolean {

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {

                if (ContextCompat.checkSelfPermission(
                        context,
                        Manifest.permission.NEARBY_WIFI_DEVICES
                    ) != PackageManager.PERMISSION_GRANTED
                ) {
                    return false
                }
            }

            return ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    fun hasPermission(): Boolean {
        return hasWifiPermission(activity)
    }

    fun getPermissions(): Array<String> {

        val permissions = mutableListOf(Manifest.permission.ACCESS_FINE_LOCATION)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.NEARBY_WIFI_DEVICES)
        }

        return permissions.toTypedArray()
    }

    fun requestPermission() {

        val permissions = mutableListOf<String>()

        if (ContextCompat.checkSelfPermission(
                activity,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            permissions.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {

            if (ContextCompat.checkSelfPermission(
                    activity,
                    Manifest.permission.NEARBY_WIFI_DEVICES
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                permissions.add(Manifest.permission.NEARBY_WIFI_DEVICES)
            }
        }

        if (permissions.isNotEmpty()) {

            ActivityCompat.requestPermissions(
                activity,
                permissions.toTypedArray(),
                REQUEST_WIFI_PERMISSION
            )
        }
    }

    /**
     * Call from Activity.onRequestPermissionsResult.
     * Returns true only if this callback belongs to us AND all permissions were granted.
     */
    fun handleResult(requestCode: Int, grantResults: IntArray): Boolean {

        if (requestCode != REQUEST_WIFI_PERMISSION) {
            return false
        }

        if (grantResults.isEmpty()) {
            return false
        }

        for (result in grantResults) {
            if (result != PackageManager.PERMISSION_GRANTED) {
                return false
            }
        }

        return true
    }
}
