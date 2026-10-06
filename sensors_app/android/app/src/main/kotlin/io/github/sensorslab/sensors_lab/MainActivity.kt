package io.github.sensorslab.sensors_lab

import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.GeomagneticField
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the phone's sensors to Flutter.
 *
 * Security notes:
 * - Every request from Dart is validated against fixed allow-lists (sensor
 *   types, sampling rates, permission names); anything else is refused.
 * - Sensing stops whenever the app leaves the screen (onStop) and resumes on
 *   return, so nothing is measured in the background.
 * - Readings stay in memory: nothing is written to disk or sent anywhere
 *   (the app does not even hold the INTERNET permission).
 *
 * FlutterFragmentActivity (not FlutterActivity) because local_auth needs it.
 */
class MainActivity : FlutterFragmentActivity() {
    private val streams = mutableListOf<Pausable>()
    private lateinit var permissionRequester: PermissionRequester

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        permissionRequester = PermissionRequester(this)

        // One event channel per sensor type, so several sensors can stream at once.
        for (type in SensorStream.ALLOWED_TYPES) {
            val handler = SensorStream(this, type, permissionRequester)
            streams += handler
            EventChannel(messenger, "sensors_lab/sensor/$type").setStreamHandler(handler)
        }
        LocationStream(this, permissionRequester).also {
            streams += it
            EventChannel(messenger, "sensors_lab/location").setStreamHandler(it)
        }
        SoundLevelStream(this, permissionRequester).also {
            streams += it
            EventChannel(messenger, "sensors_lab/sound").setStreamHandler(it)
        }

        MethodChannel(messenger, "sensors_lab/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "sensors" -> result.success(SensorStream.describeAll(this))
                "declination" -> {
                    val lat = call.argument<Double>("lat")
                    val lon = call.argument<Double>("lon")
                    if (lat == null || lon == null || lat !in -90.0..90.0 || lon !in -180.0..180.0) {
                        result.error("BAD_ARGS", "lat/lon out of range", null)
                    } else {
                        val field = GeomagneticField(lat.toFloat(), lon.toFloat(), 0f, System.currentTimeMillis())
                        result.success(field.declination.toDouble())
                    }
                }
                "permissionStatus" -> {
                    val perms = PermissionRequester.resolve(call.argument<String>("name"))
                    if (perms == null) result.error("BAD_ARGS", "unknown permission", null)
                    else result.success(perms.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED })
                }
                "requestPermission" -> permissionRequester.request(call.argument<String>("name"), result)
                "openAppSettings" -> {
                    // Only ever this app's own settings page.
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Activity Result API is not used: plain runtime permissions keep this dependency-free")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        @Suppress("DEPRECATION")
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (::permissionRequester.isInitialized) permissionRequester.onResult(requestCode, grantResults)
    }

    override fun onStart() {
        super.onStart()
        streams.forEach { it.resume() }
    }

    override fun onStop() {
        streams.forEach { it.pause() }
        super.onStop()
    }

    override fun onDestroy() {
        streams.forEach { it.pause() }
        super.onDestroy()
    }
}

/** A stream that must not run while the app is in the background. */
interface Pausable {
    fun pause()
    fun resume()
}
