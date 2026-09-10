package com.almobarmg.samafox

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Environment
import android.os.IBinder
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * A11 — "تسجيل الشاشة بدون صوت".
 *
 * ── Why this class has to exist at all ───────────────────────────────────────
 *
 * The client is recording with the phone's own built-in recorder and getting
 * silence. That is not an app bug and no amount of app code can fix it: the
 * system recorder captures internal audio through `AudioPlaybackCapture`, and
 * that API is FORBIDDEN BY THE PLATFORM from capturing streams whose usage is
 * `USAGE_VOICE_COMMUNICATION`. WebRTC uses exactly that usage for the room's
 * voice, and it is the same rule that stops any app recording a phone call.
 *
 * So a recorder inside the app, capturing the MICROPHONE, is the only route to
 * a recording with sound. What that gives:
 *
 *   • the user's own voice — always, cleanly;
 *   • the other speakers in the room — when the room is on the LOUDSPEAKER,
 *     because their voices come out of the speaker and back in through the mic.
 *     On the earpiece they will be faint or absent, and no API can change that.
 *
 * This is worth stating to the owner plainly rather than letting him discover
 * it: "record the room's audio exactly as the app hears it" is not something
 * Android permits, for anyone.
 *
 * ── Notes on the implementation ──────────────────────────────────────────────
 *
 * From Android 10 a MediaProjection capture must run inside a foreground
 * service, and from Android 14 that service must already be in the foreground
 * *before* the projection is obtained — hence [start] taking the consent Intent
 * and doing the projection work in [onStartCommand] rather than in the
 * Activity.
 *
 * Follows RoomAudioService: platform `Notification.Builder`, no androidx, so
 * this module keeps needing no dependency of its own.
 */
class ScreenRecordService : Service() {

    companion object {
        private const val TAG = "ScreenRecordService"

        const val ACTION_START = "com.almobarmg.samafox.action.START_RECORD"
        const val ACTION_STOP = "com.almobarmg.samafox.action.STOP_RECORD"

        private const val EXTRA_RESULT_CODE = "resultCode"
        private const val EXTRA_RESULT_INTENT = "resultIntent"

        private const val CHANNEL_ID = "samafox_screen_record"
        private const val NOTIFICATION_ID = 4202

        /** Set while a recording is running; read by the method channel. */
        @Volatile
        var isRecording: Boolean = false
            private set

        /** Path of the finished file, for the Dart side to report back. */
        @Volatile
        var lastOutputPath: String? = null
            private set

        fun start(context: Context, resultCode: Int, data: Intent) {
            val intent = Intent(context, ScreenRecordService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_RESULT_CODE, resultCode)
                putExtra(EXTRA_RESULT_INTENT, data)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, ScreenRecordService::class.java).apply { action = ACTION_STOP }
            )
        }
    }

    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var recorder: MediaRecorder? = null
    private var outputFile: File? = null

    /**
     * Android 14 revokes a projection when the app stops it from elsewhere, and
     * requires a registered callback. Without one, `getMediaProjection` throws.
     */
    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            Log.i(TAG, "projection stopped by the system")
            stopRecording()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopRecording()
                stopSelf()
            }
            ACTION_START -> {
                // Foreground FIRST — on Android 14 the projection cannot be
                // obtained until the service is already foregrounded.
                goForeground()

                val code = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
                @Suppress("DEPRECATION")
                val data = intent.getParcelableExtra<Intent>(EXTRA_RESULT_INTENT)
                if (code != Activity.RESULT_OK || data == null) {
                    Log.w(TAG, "no projection consent; stopping")
                    stopSelf()
                    return START_NOT_STICKY
                }
                if (!beginRecording(code, data)) stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun goForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "تسجيل الشاشة",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { setShowBadge(false) }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val notification = builder
            .setContentTitle("جارٍ تسجيل الشاشة")
            .setContentText("اضغط لإيقاف التسجيل من داخل التطبيق")
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun beginRecording(resultCode: Int, data: Intent): Boolean {
        return try {
            val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val mp = manager.getMediaProjection(resultCode, data) ?: return false
            projection = mp
            mp.registerCallback(projectionCallback, null)

            val metrics = screenMetrics()
            // Cap the long edge at 1280 so a 1440p phone does not produce a
            // file too large to share — the point of these recordings is to
            // send them to someone.
            val scale = minOf(1f, 1280f / maxOf(metrics.widthPixels, metrics.heightPixels))
            // Encoders reject odd dimensions; round to an even number.
            val width = ((metrics.widthPixels * scale).toInt() / 2) * 2
            val height = ((metrics.heightPixels * scale).toInt() / 2) * 2

            val file = newOutputFile()
            outputFile = file

            val rec = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }

            // Order matters to MediaRecorder: sources, then format, then the
            // per-track settings, then prepare.
            //
            // MIC, not an internal-audio capture: see the class comment. The
            // room's voice is USAGE_VOICE_COMMUNICATION and the platform does
            // not allow it to be captured.
            rec.setAudioSource(MediaRecorder.AudioSource.MIC)
            rec.setVideoSource(MediaRecorder.VideoSource.SURFACE)
            rec.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            rec.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            rec.setAudioEncodingBitRate(128_000)
            rec.setAudioSamplingRate(44_100)
            rec.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            rec.setVideoSize(width, height)
            rec.setVideoFrameRate(30)
            rec.setVideoEncodingBitRate(width * height * 4)
            rec.setOutputFile(file.absolutePath)
            rec.prepare()

            virtualDisplay = mp.createVirtualDisplay(
                "SamaFoxScreen",
                width,
                height,
                metrics.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                rec.surface,
                null,
                null,
            )

            rec.start()
            recorder = rec
            isRecording = true
            lastOutputPath = file.absolutePath
            Log.i(TAG, "recording to ${file.absolutePath} at ${width}x$height")
            true
        } catch (e: Exception) {
            Log.e(TAG, "failed to start recording", e)
            releaseAll()
            false
        }
    }

    private fun stopRecording() {
        if (!isRecording && recorder == null) return
        try {
            // stop() throws if the recorder never got a frame — a recording
            // ended within a few hundred ms of starting. The file is useless
            // either way; do not let it crash the app.
            recorder?.stop()
        } catch (e: Exception) {
            Log.w(TAG, "recorder.stop() failed (recording was probably too short)", e)
            outputFile?.delete()
            lastOutputPath = null
        }
        releaseAll()
    }

    private fun releaseAll() {
        try { recorder?.reset() } catch (_: Exception) {}
        try { recorder?.release() } catch (_: Exception) {}
        recorder = null

        try { virtualDisplay?.release() } catch (_: Exception) {}
        virtualDisplay = null

        try { projection?.unregisterCallback(projectionCallback) } catch (_: Exception) {}
        try { projection?.stop() } catch (_: Exception) {}
        projection = null

        isRecording = false

        // minSdk is 24, so STOP_FOREGROUND_REMOVE (API 24) always exists here.
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun newOutputFile(): File {
        val dir = File(
            getExternalFilesDir(Environment.DIRECTORY_MOVIES) ?: filesDir,
            "recordings",
        )
        if (!dir.exists()) dir.mkdirs()
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        return File(dir, "samafox_$stamp.mp4")
    }

    @Suppress("DEPRECATION")
    private fun screenMetrics(): DisplayMetrics {
        val metrics = DisplayMetrics()
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        wm.defaultDisplay.getRealMetrics(metrics)
        return metrics
    }

    override fun onDestroy() {
        stopRecording()
        super.onDestroy()
    }
}
