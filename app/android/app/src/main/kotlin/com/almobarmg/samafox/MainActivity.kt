package com.almobarmg.samafox

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Debug
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * A23 — the Dart side asks for the mic foreground service to be running while
 * the user holds a seat, and to stop the moment they leave it.
 *
 * A11 — and asks to start/stop a screen recording. Screen capture needs the
 * user's consent through a system dialog, and that dialog can only be raised by
 * an Activity, so the request is launched here and its result handed to
 * [ScreenRecordService].
 *
 * A method channel rather than plugin dependencies: this is platform glue, and
 * adding packages would mean a `pub get` on a machine whose disk has been full
 * for days.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "samafox/room_audio"
        const val RECORD_CHANNEL = "samafox/screen_record"
        const val MEM_CHANNEL = "samafox/memory"
        const val REQ_PROJECTION = 7311
    }

    /** Answered once the consent dialog comes back. */
    private var pendingRecordResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        RoomAudioService.start(
                            this,
                            call.argument<String>("roomName"),
                            call.argument<Boolean>("onMic") ?: false,
                        )
                        result.success(true)
                    }
                    "stop" -> {
                        RoomAudioService.stop(this)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RECORD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isRecording" -> result.success(ScreenRecordService.isRecording)

                    "start" -> {
                        if (ScreenRecordService.isRecording) {
                            result.success(false)
                        } else if (pendingRecordResult != null) {
                            // A consent dialog is already up; a second tap must
                            // not strand the first result.
                            result.success(false)
                        } else {
                            pendingRecordResult = result
                            val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                                as MediaProjectionManager
                            startActivityForResult(
                                manager.createScreenCaptureIntent(),
                                REQ_PROJECTION,
                            )
                        }
                    }

                    "stop" -> {
                        ScreenRecordService.stop(this)
                        // The path is captured when the file is created, so it
                        // is already known by the time stop is asked for.
                        result.success(ScreenRecordService.lastOutputPath)
                    }

                    else -> result.notImplemented()
                }
            }

        // Where the resident memory actually is. `ProcessInfo.currentRss` on the
        // Dart side says HOW MUCH; only the OS can say WHAT — Java heap, native
        // heap (video decoders, webrtc, Dart's own heap), graphics (GPU textures
        // and surfaces) or code. This is `dumpsys meminfo` for a phone nobody can
        // plug into a computer.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "breakdown" -> {
                        val info = Debug.MemoryInfo()
                        Debug.getMemoryInfo(info)
                        val stats = info.memoryStats
                        // Values are KB strings; keep only the summary rows.
                        val out = HashMap<String, Int>()
                        for ((k, v) in stats) {
                            if (k.startsWith("summary.")) {
                                out[k.removePrefix("summary.")] = v.toIntOrNull() ?: 0
                            }
                        }
                        result.success(out)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // startActivityForResult is the only API that raises the screen-capture
    // consent dialog; the Activity Result API cannot replace it here because the
    // request has to come from this Activity for the projection token to be
    // valid.
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PROJECTION) return

        val result = pendingRecordResult
        pendingRecordResult = null

        if (resultCode == Activity.RESULT_OK && data != null) {
            ScreenRecordService.start(this, resultCode, data)
            result?.success(true)
        } else {
            // Declined, or dismissed. Not an error — the user said no.
            result?.success(false)
        }
    }
}
