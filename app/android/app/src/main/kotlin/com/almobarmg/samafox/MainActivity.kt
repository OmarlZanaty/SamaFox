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
                    // Off the main thread: a native crash's tombstone is read
                    // and decoded here, and it can run to a few hundred KB.
                    "lastExit" -> Thread {
                        val info = lastExitInfo()
                        Handler(Looper.getMainLooper()).post { result.success(info) }
                    }.start()
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
                "trace" to if (info.reason == 5) nativeCrashSummary(info) else null,
            )
        } catch (e: Throwable) {
            null
        }
    }

    /**
     * The crashing thread's backtrace from a native crash's tombstone (API 31+).
     *
     * The exit reason alone said "CRASH_NATIVE status=6" for sixteen crashes on
     * 29/09, all during WebRTC peer churn, with nothing to say which call
     * aborted. Android keeps the tombstone for us as a protobuf; this decodes
     * the handful of fields that answer that: signal, abort message, the
     * crashing thread's frames, and the last error lines it logged.
     */
    private fun nativeCrashSummary(info: android.app.ApplicationExitInfo): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        return try {
            val bytes = info.traceInputStream?.use { input ->
                val out = java.io.ByteArrayOutputStream()
                val buf = ByteArray(16 * 1024)
                while (out.size() < 8 * 1024 * 1024) {
                    val n = input.read(buf)
                    if (n < 0) break
                    out.write(buf, 0, n)
                }
                out.toByteArray()
            } ?: return null
            Tombstone.summarize(bytes)
        } catch (e: Throwable) {
            "tombstone unreadable: ${e.javaClass.simpleName} ${e.message}"
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

/**
 * Just enough protobuf to read Android's tombstone.proto (system/core/debuggerd/
 * proto/tombstone.proto). Field numbers from there: Tombstone 5 pid, 6 tid,
 * 10 signal_info, 14 abort_message, 16 threads (map<uint32, Thread>),
 * 18 log_buffers. Thread 1 id, 2 name, 4 current_backtrace. BacktraceFrame
 * 1 rel_pc, 4 function_name, 5 function_offset, 6 file_name. Signal 2 name,
 * 4 code_name. LogBuffer 2 logs; LogMessage 3 tid, 4 priority, 5 tag, 6 message.
 */
private object Tombstone {
    private class Field(val number: Int, val varint: Long, val bytes: ByteArray?)

    private fun parse(data: ByteArray): List<Field> {
        val out = ArrayList<Field>()
        var i = 0
        fun varint(): Long {
            var shift = 0
            var result = 0L
            while (i < data.size) {
                val b = data[i++].toInt() and 0xff
                result = result or ((b and 0x7f).toLong() shl shift)
                if (b and 0x80 == 0) break
                shift += 7
            }
            return result
        }
        while (i < data.size) {
            val key = varint()
            val number = (key ushr 3).toInt()
            when ((key and 7).toInt()) {
                0 -> out.add(Field(number, varint(), null))
                1 -> i += 8
                2 -> {
                    val len = varint().toInt()
                    if (len < 0 || i + len > data.size) return out
                    out.add(Field(number, 0, data.copyOfRange(i, i + len)))
                    i += len
                }
                5 -> i += 4
                else -> return out // not protobuf we understand; keep what we have
            }
        }
        return out
    }

    private fun str(fields: List<Field>, n: Int) =
        fields.firstOrNull { it.number == n }?.bytes?.let { String(it, Charsets.UTF_8) }

    private fun num(fields: List<Field>, n: Int) =
        fields.firstOrNull { it.number == n }?.varint

    fun summarize(data: ByteArray): String {
        val top = parse(data)
        val sb = StringBuilder()
        val tid = num(top, 6)
        top.firstOrNull { it.number == 10 }?.bytes?.let { sig ->
            val f = parse(sig)
            sb.appendLine("signal ${str(f, 2)} ${str(f, 4) ?: ""}")
        }
        str(top, 14)?.takeIf { it.isNotBlank() }?.let { sb.appendLine("abort: ${it.take(1500)}") }

        // The crashing thread, else the first one listed.
        val threads = top.filter { it.number == 16 }.mapNotNull { e ->
            val entry = parse(e.bytes ?: return@mapNotNull null)
            val key = num(entry, 1)
            val value = entry.firstOrNull { it.number == 2 }?.bytes ?: return@mapNotNull null
            key to parse(value)
        }
        val crashing = threads.firstOrNull { it.first == tid }?.second ?: threads.firstOrNull()?.second
        if (crashing != null) {
            sb.appendLine("thread ${str(crashing, 2)} tid=$tid")
            crashing.filter { it.number == 4 }.take(40).forEachIndexed { idx, fr ->
                val f = parse(fr.bytes ?: return@forEachIndexed)
                val fn = str(f, 4)?.takeIf { it.isNotEmpty() } ?: "?"
                val off = num(f, 5) ?: 0
                val file = str(f, 6)?.substringAfterLast('/') ?: "?"
                val pc = java.lang.Long.toHexString(num(f, 1) ?: 0)
                sb.appendLine("#$idx $file pc $pc $fn+$off")
            }
        }

        // Last error/fatal log lines of the crashing thread — an RTC_CHECK
        // prints its "Check failed" here before aborting.
        val lines = ArrayList<String>()
        top.filter { it.number == 18 }.forEach { buf ->
            parse(buf.bytes ?: return@forEach).filter { it.number == 2 }.forEach { m ->
                val f = parse(m.bytes ?: return@forEach)
                if ((num(f, 4) ?: 0) >= 6 && (tid == null || num(f, 3) == tid)) {
                    lines.add("${str(f, 5)}: ${str(f, 6)?.take(300)}")
                }
            }
        }
        lines.takeLast(12).forEach { sb.appendLine("log $it") }
        return sb.toString().take(7800)
    }
}
