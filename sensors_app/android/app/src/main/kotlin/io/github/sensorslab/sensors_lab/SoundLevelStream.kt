package io.github.sensorslab.sensors_lab

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Microphone as a sound-level meter. Only the loudness (dBFS) of each
 * 100 ms block leaves this class; the audio itself is never kept, saved or
 * sent anywhere.
 */
class SoundLevelStream(
    @Suppress("unused") context: Context,
    private val permissions: PermissionRequester,
) : EventChannel.StreamHandler, Pausable {
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    @Volatile private var running = false
    private var thread: Thread? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        if (!permissions.granted(Manifest.permission.RECORD_AUDIO)) {
            events.error("PERMISSION", "microphone not granted", null)
            return
        }
        sink = events
        start()
    }

    override fun onCancel(arguments: Any?) {
        stop()
        sink = null
    }

    override fun pause() = stop()

    override fun resume() {
        if (sink != null) start()
    }

    @SuppressLint("MissingPermission") // checked just below
    private fun start() {
        if (running || !permissions.granted(Manifest.permission.RECORD_AUDIO)) return
        val minBuf = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (minBuf <= 0) {
            sink?.error("UNAVAILABLE", "microphone unavailable", null)
            return
        }
        val record = try {
            AudioRecord(MediaRecorder.AudioSource.MIC, RATE, AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT, max(minBuf, BLOCK * 2))
        } catch (e: IllegalArgumentException) {
            sink?.error("UNAVAILABLE", "microphone unavailable", null)
            return
        }
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            sink?.error("UNAVAILABLE", "microphone busy", null)
            return
        }
        running = true
        thread = Thread({
            val buf = ShortArray(BLOCK)
            try {
                record.startRecording()
                while (running) {
                    val n = record.read(buf, 0, buf.size)
                    if (n <= 0) continue
                    var sum = 0.0
                    for (i in 0 until n) sum += buf[i].toDouble() * buf[i]
                    val rms = sqrt(sum / n) / Short.MAX_VALUE
                    val db = if (rms > 0) max(-90.0, 20 * log10(rms)) else -90.0
                    main.post { if (running) sink?.success(db) }
                }
            } finally {
                buf.fill(0)
                runCatching { record.stop() }
                record.release()
            }
        }, "sound-level").apply { start() }
    }

    private fun stop() {
        running = false
        thread?.join(500)
        thread = null
    }

    companion object {
        private const val RATE = 16_000
        private const val BLOCK = RATE / 10
    }
}
