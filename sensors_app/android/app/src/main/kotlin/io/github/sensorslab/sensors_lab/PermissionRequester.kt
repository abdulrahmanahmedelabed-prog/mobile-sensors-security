package io.github.sensorslab.sensors_lab

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import io.flutter.plugin.common.MethodChannel

/** Runtime permission requests, limited to the few this app declares. */
class PermissionRequester(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null

    fun granted(vararg perms: String): Boolean =
        perms.all { activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    fun request(name: String?, result: MethodChannel.Result) {
        val perms = resolve(name)
        when {
            perms == null -> result.error("BAD_ARGS", "unknown permission", null)
            granted(*perms) -> result.success(true)
            pending != null -> result.error("BUSY", "another permission request is open", null)
            else -> {
                pending = result
                activity.requestPermissions(perms, REQUEST_CODE)
            }
        }
    }

    fun onResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_CODE) return
        val result = pending ?: return
        pending = null
        // Coarse location alone is enough when the user declines precise location.
        result.success(grantResults.isNotEmpty() && grantResults.any { it == PackageManager.PERMISSION_GRANTED })
    }

    companion object {
        private const val REQUEST_CODE = 4201

        fun resolve(name: String?): Array<String>? = when (name) {
            "location_coarse" -> arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION)
            "location_fine" -> arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
            "microphone" -> arrayOf(Manifest.permission.RECORD_AUDIO)
            "camera" -> arrayOf(Manifest.permission.CAMERA)
            "activity" -> arrayOf(Manifest.permission.ACTIVITY_RECOGNITION)
            else -> null
        }
    }
}
