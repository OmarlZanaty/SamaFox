package com.almobarmg.samafox

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.AudioRecordingConfiguration
import android.media.MediaRecorder
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.provider.Settings
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
        const val DEVICE_CHANNEL = "samafox/device"
        const val MIC_SHARE_CHANNEL = "samafox/mic_share"
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

        // F4 — the id a device ban sticks to. device_info_plus's `androidInfo.id`
        // is Build.ID, the FIRMWARE build ("AP3A.240905.015.A2"), shared by every
        // phone of that model and update — banning it banned all of them.
        // ANDROID_ID is per device (and per signing key), and survives reinstall.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "androidId" -> result.success(
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                    )
                    else -> result.notImplemented()
                }
            }

        // Sharing the microphone with other apps ("فويس الواتس مش بيشتغل وانا
        // على المايك"). While we hold the phone in communication mode Android
        // gives US the microphone, even over the app on screen: a WhatsApp voice
        // note recorded silence. So we watch for anyone else recording — any
        // source other than VOICE_COMMUNICATION, which is ours (WebRTC and the
        // screen recorder both use it) — and tell Dart, which hands the mic
        // over; [yieldCommunication] drops the call mode that gives us priority.
        val micShare = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MIC_SHARE_CHANNEL)
        micShareChannel = micShare
        micShare.setMethodCallHandler { call, result ->
            when (call.method) {
                "watch" -> { watchRecordings(); result.success(true) }
                "unwatch" -> { unwatchRecordings(); result.success(true) }
                "yieldCommunication" -> {
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    if (savedAudioMode == null && am.mode != AudioManager.MODE_NORMAL) {
                        savedAudioMode = am.mode
                        am.mode = AudioManager.MODE_NORMAL
                    }
                    result.success(true)
                }
                "restoreCommunication" -> {
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    savedAudioMode?.let { am.mode = it }
                    savedAudioMode = null
                    result.success(true)
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
                    "lastExit" -> result.success(lastExitInfo())
                    else -> result.notImplemented()
                }
            }
    }

    private var micShareChannel: MethodChannel? = null
    private var recordingCallback: AudioManager.AudioRecordingCallback? = null
    private var othersRecording = false
    /** The mode we left when handing the mic over, restored when taking it back. */
    private var savedAudioMode: Int? = null

    private fun watchRecordings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N || recordingCallback != null) return
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val cb = object : AudioManager.AudioRecordingCallback() {
            override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>?) {
                val others = configs.orEmpty().any {
                    it.clientAudioSource != MediaRecorder.AudioSource.VOICE_COMMUNICATION
                }
                if (others == othersRecording) return
                othersRecording = others
                micShareChannel?.invokeMethod("othersRecording", others)
            }
        }
        am.registerAudioRecordingCallback(cb, Handler(Looper.getMainLooper()))
        recordingCallback = cb
    }

    private fun unwatchRecordings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        val cb = recordingCallback ?: return
        (getSystemService(Context.AUDIO_SERVICE) as AudioManager).unregisterAudioRecordingCallback(cb)
        recordingCallback = null
        othersRecording = false
    }

    override fun onDestroy() {
        unwatchRecordings()
        micShareChannel = null
        super.onDestroy()
    }

    /**
     * Why the PREVIOUS process died, as Android recorded it (API 30+). The Dart
     * side only knows "the session marker was left behind", which lumps a
     * low-memory kill, a native crash in libwebrtc and the user swiping the app
     * away into one "processKilled". This tells them apart, and `importance`
     * says whether the app was on screen or in the background at the time.
     */
    private fun lastExitInfo(): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val me = android.os.Process.myPid()
            val info = am.getHistoricalProcessExitReasons(null, 0, 5)
                .firstOrNull { it.pid != me } ?: return null
            mapOf(
                "reason" to exitReasonName(info.reason),
                "importance" to importanceName(info.importance),
                "status" to info.status,
                "description" to info.description,
                "pssMb" to (info.pss / 1024).toInt(),
                "rssMb" to (info.rss / 1024).toInt(),
                "at" to info.timestamp,
            )
        } catch (e: Throwable) {
            null
        }
    }

    // Literal codes rather than the constants: several were added after API 30
    // and this must compile and run on every level the app supports.
    private fun exitReasonName(reason: Int): String = when (reason) {
        1 -> "EXIT_SELF"
        2 -> "SIGNALED"
        3 -> "LOW_MEMORY"
        4 -> "CRASH"
        5 -> "CRASH_NATIVE"
        6 -> "ANR"
        7 -> "INITIALIZATION_FAILURE"
        8 -> "PERMISSION_CHANGE"
        9 -> "EXCESSIVE_RESOURCE_USAGE"
        10 -> "USER_REQUESTED"
        11 -> "USER_STOPPED"
        12 -> "DEPENDENCY_DIED"
        13 -> "OTHER"
        14 -> "FREEZER"
        15 -> "PACKAGE_STATE_CHANGE"
        16 -> "PACKAGE_UPDATED"
        else -> "UNKNOWN($reason)"
    }

    private fun importanceName(importance: Int): String = when {
        importance <= 100 -> "foreground"
        importance <= 125 -> "foreground-service"
        importance <= 230 -> "visible"
        importance <= 325 -> "service"
        importance < 1000 -> "background"
        else -> "gone"
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
