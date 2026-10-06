package io.github.sensorslab.sensors_lab

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * GPS / network location. Uses GPS only when the user granted precise
 * location; with approximate location the network provider is enough
 * (e.g. for the Qibla direction).
 */
class LocationStream(
    context: Context,
    private val permissions: PermissionRequester,
) : EventChannel.StreamHandler, LocationListener, Pausable {
    private val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private var sink: EventChannel.EventSink? = null
    private var registered = false

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        if (!permissions.granted(Manifest.permission.ACCESS_COARSE_LOCATION)) {
            events.error("PERMISSION", "location not granted", null)
            return
        }
        if (!manager.isLocationEnabled) {
            events.error("DISABLED", "location is turned off", null)
            return
        }
        sink = events
        register()
    }

    override fun onCancel(arguments: Any?) {
        unregister()
        sink = null
    }

    override fun pause() = unregister()

    override fun resume() {
        if (sink != null) register()
    }

    @SuppressLint("MissingPermission") // checked in hasAnyLocationPermission()
    private fun register() {
        if (registered || !hasAnyLocationPermission()) return
        val precise = permissions.granted(Manifest.permission.ACCESS_FINE_LOCATION)
        val providers = buildList {
            if (precise && manager.isProviderEnabled(LocationManager.GPS_PROVIDER)) add(LocationManager.GPS_PROVIDER)
            if (manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) add(LocationManager.NETWORK_PROVIDER)
        }
        if (providers.isEmpty()) {
            sink?.error("DISABLED", "no location provider enabled", null)
            return
        }
        providers.mapNotNull { manager.getLastKnownLocation(it) }.maxByOrNull { it.time }?.let(::onLocationChanged)
        for (p in providers) manager.requestLocationUpdates(p, 2000L, 0f, this, Looper.getMainLooper())
        registered = true
    }

    private fun hasAnyLocationPermission() =
        permissions.granted(Manifest.permission.ACCESS_COARSE_LOCATION) ||
            permissions.granted(Manifest.permission.ACCESS_FINE_LOCATION)

    private fun unregister() {
        if (!registered) return
        manager.removeUpdates(this)
        registered = false
    }

    override fun onLocationChanged(location: Location) {
        sink?.success(
            mapOf(
                "lat" to location.latitude,
                "lon" to location.longitude,
                "accuracy" to location.accuracy.toDouble(),
                "altitude" to if (location.hasAltitude()) location.altitude else null,
                "speed" to if (location.hasSpeed()) location.speed.toDouble() else null,
                "bearing" to if (location.hasBearing()) location.bearing.toDouble() else null,
                "provider" to location.provider,
                "time" to location.time,
            ),
        )
    }

    @Deprecated("Required on API < 29")
    override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) = Unit
    override fun onProviderEnabled(provider: String) = Unit
    override fun onProviderDisabled(provider: String) = Unit
}
