package com.almobarmg.samafox

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.media.MediaScannerConnection
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.*
import android.provider.MediaStore
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import java.io.File
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Owns projection consent, foreground lifetime and gallery publication.
 * Codecs, mixing and storage finalization run on the encoder worker. */
class ScreenRecordService : Service() {
    companion object {
        private const val START = "samafox.record.START"
        private const val STOP = "samafox.record.STOP"
        private const val CHANNEL = "samafox_screen_record"
        private const val NOTIFICATION = 4202
        @Volatile var isRecording = false
            private set
        @Volatile var lastOutputPath: String? = null
            private set
        @Volatile var roomAudioIncluded = false
            private set
        var events: ((Map<String, Any?>) -> Unit)? = null
        private var startReply: ((Boolean) -> Unit)? = null
        private val stopReplies = mutableListOf<(String?) -> Unit>()
        private var instance: ScreenRecordService? = null
        private var starting = false
        private var stopRequested = false

        fun start(context: Context, code: Int, data: Intent, reply: (Boolean) -> Unit) {
            if (starting || instance != null) { reply(false); return }
            starting = true; stopRequested = false; startReply = reply
            lastOutputPath = null; roomAudioIncluded = false
            val intent = Intent(context, ScreenRecordService::class.java).setAction(START)
                .putExtra("code", code).putExtra("data", data)
            try {
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
            } catch (e: Exception) {
                starting = false; startReply = null; reply(false)
                events?.invoke(mapOf("recording" to false, "error" to "تعذر بدء التسجيل"))
            }
        }

        fun stop(context: Context, reply: (String?) -> Unit = {}) {
            if (instance == null && !starting) { reply(null); return }
            stopReplies.add(reply)
            stopRequested = true
            instance?.encoder?.stop()
        }
    }

    private var projection: MediaProjection? = null
    private var encoder: ScreenRecordingEncoder? = null
    private var outputUri: Uri? = null
    private var outputFile: File? = null
    private var outputName = ""
    private val main = Handler(Looper.getMainLooper())
    private var finished = false
    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() { encoder?.stop() }
    }
    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { encoder?.stop() }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF), RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF))
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) { encoder?.stop(); return START_NOT_STICKY }
        if (intent?.action != START || encoder != null) return START_NOT_STICKY
        try {
            goForeground()
            val code = intent.getIntExtra("code", Activity.RESULT_CANCELED)
            @Suppress("DEPRECATION") val data = intent.getParcelableExtra<Intent>("data")
            require(code == Activity.RESULT_OK && data != null)
            val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val mp = manager.getMediaProjection(code, data) ?: error("Projection unavailable")
            projection = mp
            mp.registerCallback(projectionCallback, main)
            outputName = "SAMAFOX_${SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())}.mp4"
            var descriptor: ParcelFileDescriptor? = null
            if (Build.VERSION.SDK_INT >= 29) {
                val values = ContentValues().apply {
                    put(MediaStore.Video.Media.DISPLAY_NAME, outputName)
                    put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                    put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/SamaFox")
                    put(MediaStore.Video.Media.IS_PENDING, 1)
                }
                outputUri = contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
                    ?: error("MediaStore insert failed")
                descriptor = contentResolver.openFileDescriptor(outputUri!!, "rw") ?: error("MediaStore open failed")
            } else {
                val directory = File(getExternalFilesDir(Environment.DIRECTORY_MOVIES), "recordings").apply { mkdirs() }
                outputFile = File(directory, outputName)
            }
            encoder = ScreenRecordingEncoder(this, mp, metrics(), descriptor, outputFile,
                started = { roomAudio -> main.post {
                    roomAudioIncluded = roomAudio
                    isRecording = !stopRequested
                    starting = false
                    startReply?.invoke(!stopRequested); startReply = null
                    events?.invoke(mapOf("recording" to isRecording, "roomAudioIncluded" to roomAudio))
                    if (stopRequested) encoder?.stop()
                } },
                completed = { usable, error -> finalizeOutput(usable, error) })
            encoder!!.start()
        } catch (e: Exception) {
            Log.e("SamaFoxRecord", "start failed", e)
            Thread({ finalizeOutput(false, e.message) }, "samafox-record-cleanup").start()
        }
        return START_NOT_STICKY
    }

    private fun finalizeOutput(usable: Boolean, error: String?) {
        var uri: Uri? = null
        var legacyPublished: File? = null
        try {
            if (usable && Build.VERSION.SDK_INT >= 29) {
                check(contentResolver.update(outputUri!!, ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }, null, null) == 1)
                uri = outputUri
            } else if (usable) {
                @Suppress("DEPRECATION")
                val directory = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "SamaFox").apply { mkdirs() }
                val published = File(directory, outputName)
                legacyPublished = published
                outputFile!!.copyTo(published, overwrite = false)
                val scanned = CountDownLatch(1)
                var scannedUri: Uri? = null
                MediaScannerConnection.scanFile(this, arrayOf(published.absolutePath), arrayOf("video/mp4")) { _, result ->
                    scannedUri = result; scanned.countDown()
                }
                scanned.await(10, TimeUnit.SECONDS)
                uri = scannedUri
            }
        } catch (e: Exception) { Log.e("SamaFoxRecord", "gallery publish failed", e) }
        if (uri == null) {
            outputUri?.let { runCatching { contentResolver.delete(it, null, null) } }
            legacyPublished?.delete()
        }
        outputFile?.delete()
        val saved = uri?.toString()
        main.post {
            if (finished) return@post
            finished = true
            if (error != null) Log.w("SamaFoxRecord", error)
            isRecording = false; starting = false; lastOutputPath = saved
            startReply?.invoke(false); startReply = null
            val replies = stopReplies.toList(); stopReplies.clear()
            replies.forEach { it(saved) }
            events?.invoke(mapOf("recording" to false, "uri" to saved,
                "error" to if (saved == null) "تعذر حفظ التسجيل أو كان قصيراً جداً" else null))
            projection?.unregisterCallback(projectionCallback)
            projection?.stop(); projection = null
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun goForeground() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(CHANNEL, "تسجيل الشاشة", NotificationManager.IMPORTANCE_LOW))
        val stop = PendingIntent.getService(this, 0, Intent(this, ScreenRecordService::class.java).setAction(STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        val notification = builder.setContentTitle("جارٍ تسجيل الشاشة").setContentText("اضغط لإيقاف التسجيل وحفظه")
            .setSmallIcon(android.R.drawable.presence_video_online).setContentIntent(stop).setOngoing(true).build()
        // Android 14 throws for a microphone-type service without RECORD_AUDIO;
        // the projection alone still records screen + app playback.
        val micGranted = checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or
                (if (micGranted) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0))
        else startForeground(NOTIFICATION, notification)
    }

    @Suppress("DEPRECATION")
    private fun metrics(): DisplayMetrics = DisplayMetrics().also {
        (getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(it)
    }

    override fun onDestroy() {
        encoder?.stop()
        runCatching { unregisterReceiver(screenOff) }
        if (instance === this) instance = null
        super.onDestroy()
    }
}
