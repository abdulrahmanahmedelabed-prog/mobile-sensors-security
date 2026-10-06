package io.github.sensorslab.sensors_lab

import android.Manifest
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock
import io.flutter.plugin.common.EventChannel

/** Streams one Android sensor type to Dart as [values..., accuracy]. */
class SensorStream(
    context: Context,
    private val type: Int,
    private val permissions: PermissionRequester,
) : EventChannel.StreamHandler, SensorEventListener, Pausable {
    private val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var sink: EventChannel.EventSink? = null
    private var delay = SensorManager.SENSOR_DELAY_UI
    private var registered = false
    private var lastSentNanos = 0L

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val sensor = manager.getDefaultSensor(type)
        if (sensor == null) {
            events.error("UNAVAILABLE", "this phone has no such sensor", null)
            return
        }
        if (type in STEP_TYPES && !permissions.granted(Manifest.permission.ACTIVITY_RECOGNITION)) {
            events.error("PERMISSION", "ACTIVITY_RECOGNITION not granted", null)
            return
        }
        // Only the three standard rates. SENSOR_DELAY_FASTEST is refused: it is
        // not needed here and would let a page drain the battery.
        val rate = (arguments as? Map<*, *>)?.get("rate") as? Int ?: SensorManager.SENSOR_DELAY_UI
        delay = if (rate in ALLOWED_RATES) rate else SensorManager.SENSOR_DELAY_UI
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

    private fun register() {
        if (registered) return
        val sensor = manager.getDefaultSensor(type) ?: return
        registered = manager.registerListener(this, sensor, delay)
    }

    private fun unregister() {
        if (!registered) return
        manager.unregisterListener(this)
        registered = false
    }

    override fun onSensorChanged(event: SensorEvent) {
        // At most ~60 updates a second reach Dart; the UI cannot show more.
        val now = SystemClock.elapsedRealtimeNanos()
        if (now - lastSentNanos < 16_000_000L && type !in STEP_TYPES) return
        lastSentNanos = now
        val out = ArrayList<Double>(event.values.size + 1)
        event.values.forEach { out.add(it.toDouble()) }
        out.add(event.accuracy.toDouble())
        sink?.success(out)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    companion object {
        private val ALLOWED_RATES = setOf(
            SensorManager.SENSOR_DELAY_GAME,
            SensorManager.SENSOR_DELAY_UI,
            SensorManager.SENSOR_DELAY_NORMAL,
        )
        private val STEP_TYPES = setOf(Sensor.TYPE_STEP_COUNTER, Sensor.TYPE_STEP_DETECTOR)

        /** The only sensor types Dart may open. Body sensors (heart rate) are deliberately absent. */
        val ALLOWED_TYPES = listOf(
            Sensor.TYPE_ACCELEROMETER,
            Sensor.TYPE_MAGNETIC_FIELD,
            Sensor.TYPE_GYROSCOPE,
            Sensor.TYPE_LIGHT,
            Sensor.TYPE_PRESSURE,
            Sensor.TYPE_PROXIMITY,
            Sensor.TYPE_GRAVITY,
            Sensor.TYPE_LINEAR_ACCELERATION,
            Sensor.TYPE_ROTATION_VECTOR,
            Sensor.TYPE_RELATIVE_HUMIDITY,
            Sensor.TYPE_AMBIENT_TEMPERATURE,
            Sensor.TYPE_GAME_ROTATION_VECTOR,
            Sensor.TYPE_STEP_DETECTOR,
            Sensor.TYPE_STEP_COUNTER,
        )

        /** Every sensor on the phone (for the "my phone's sensors" list). */
        fun describeAll(context: Context): List<Map<String, Any>> {
            val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
            return manager.getSensorList(Sensor.TYPE_ALL).map {
                mapOf(
                    "type" to it.type,
                    "name" to it.name,
                    "vendor" to it.vendor,
                    "maxRange" to it.maximumRange.toDouble(),
                    "resolution" to it.resolution.toDouble(),
                    "power" to it.power.toDouble(),
                    "minDelayUs" to it.minDelay,
                    "isDefault" to (manager.getDefaultSensor(it.type) == it),
                    "isWakeUp" to it.isWakeUpSensor,
                )
            }
        }
    }
}
