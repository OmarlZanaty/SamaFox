package com.almobarmg.samafox

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * A23 — the Dart side asks for the mic foreground service to be running while
 * the user holds a seat, and to stop the moment they leave it.
 *
 * A method channel rather than a plugin dependency: the service is 130 lines of
 * platform glue, and adding a package would mean a `pub get` on a machine whose
 * disk has been full for days.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "samafox/room_audio"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        RoomAudioService.start(this, call.argument<String>("roomName"))
                        result.success(true)
                    }
                    "stop" -> {
                        RoomAudioService.stop(this)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
