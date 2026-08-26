package com.almobarmg.samafox

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * A23 — "الاحتفاظ بالغرفة": keeping a mic seat while the app is in the
 * background.
 *
 * Client report (17/08 23:01): reserving the seat and leaving the app *looks*
 * right — the seat stays taken — but *"الصوت بيفصل"*, which he called a serious
 * problem: the requirement is that audio keep running *"كأنه لم يخرج من الروم
 * إطلاقاً"*.
 *
 * The cause is not app logic. From Android 9 onward a process that is not the
 * foreground app and has no foreground service loses microphone capture: the
 * peer connections stay up, the seat still looks occupied, and the track
 * produces silence. No Dart-side keep-alive can change that — the platform
 * requires a foreground service of type `microphone` for the capture to remain
 * live.
 *
 * That is this class's entire job: exist, with a visible notification, for as
 * long as the user holds a mic seat. It owns no audio — WebRTC still does — it
 * only holds the process in a state where the OS permits the capture.
 *
 * Deliberately built on the platform `Notification.Builder` rather than
 * `NotificationCompat`: this module declares no androidx dependency of its own,
 * and the pre-O branch below covers the only API the compat class would have
 * added.
 *
 * PLAY POLICY: `FOREGROUND_SERVICE_MICROPHONE` needs a matching declaration and
 * justification in Play Console. This developer account already had an app
 * rejected for exactly that gap, so the Console declaration and the store
 * listing must describe this use — "continue live voice chat while the user
 * multitasks" — before this build is submitted.
 */
class RoomAudioService : Service() {

    companion object {
        const val ACTION_STOP = "com.almobarmg.samafox.action.STOP_ROOM_AUDIO"
        const val EXTRA_ROOM_NAME = "roomName"

        private const val CHANNEL_ID = "samafox_room_audio"
        private const val NOTIFICATION_ID = 4201

        fun start(context: Context, roomName: String?) {
            val intent = Intent(context, RoomAudioService::class.java).apply {
                putExtra(EXTRA_ROOM_NAME, roomName)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, RoomAudioService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        createChannel()
        startAsForeground(buildNotification(intent?.getStringExtra(EXTRA_ROOM_NAME)))

        // Deliberately NOT sticky: if the process dies the WebRTC session dies
        // with it, and a restarted bare service would show an "on mic"
        // notification for a call that is no longer happening.
        return START_NOT_STICKY
    }

    @SuppressLint("InlinedApi")
    private fun startAsForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+ wants the type at start time; from Android 14 a
            // mismatch with the manifest declaration is a hard crash.
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "المحادثة الصوتية",
            // LOW: the notification has to exist for the OS, but it must never
            // make a sound or peek while the user is doing something else.
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "يبقي الصوت شغّالاً أثناء الاحتفاظ بالمايك خارج التطبيق"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(roomName: String?): Notification {
        // Tapping the notification returns to the running app rather than
        // launching a second copy of it.
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val contentIntent = launch?.let {
            PendingIntent.getActivity(this, 0, it, pendingFlags)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_LOW)
        }

        return builder
            .setContentTitle("المايك مفتوح")
            .setContentText(
                if (roomName.isNullOrBlank()) "أنت على المايك" else "أنت على المايك في $roomName",
            )
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_CALL)
            .apply { contentIntent?.let { setContentIntent(it) } }
            .build()
    }
}
