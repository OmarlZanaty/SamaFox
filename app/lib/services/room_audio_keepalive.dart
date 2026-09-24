import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:samafox/utils/permission_gate.dart';

/// A23 — keeps the room's voice alive while the app is in the background.
///
/// Client report (17/08 23:01): with "الاحتفاظ بالغرفة" on, leaving the app
/// keeps the seat but *"الصوت بيفصل"* — and the requirement is that it behave
/// *"كأنه لم يخرج من الروم إطلاقاً"*.
///
/// The cause is a platform rule, not app logic: from Android 9, a process that
/// is not the foreground app and has no foreground service loses microphone
/// capture. The peer connections stay up, so the seat still looks occupied,
/// while the track produces silence — exactly the symptom described.
///
/// So this class does one thing: while the user holds a mic seat, ask Android
/// to run [RoomAudioService] (foreground, type `microphone`). iOS keeps VoIP
/// audio alive through the audio session instead and needs nothing here, so
/// every call is a no-op off Android.
class RoomAudioKeepAlive {
  RoomAudioKeepAlive._();
  static final RoomAudioKeepAlive instance = RoomAudioKeepAlive._();

  static const MethodChannel _channel = MethodChannel('samafox/room_audio');

  bool _running = false;

  /// True while the foreground service is believed to be running.
  bool get isRunning => _running;

  bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Call when the user ENTERS a room, and again when they take a seat (which
  /// only refreshes the notification — starting twice is safe).
  ///
  /// A1 — this used to be called on mic-take alone, so the client's
  /// *"كأنه لم يخرج من الروم إطلاقاً"* held only for speakers. A listener who
  /// backgrounded the app had no foreground service at all: the process was
  /// freezable, the socket went with it, and they came back to a room that had
  /// stopped receiving. Everyone in the room gets the service now.
  /// [onMic] picks the notification text: a listener is told they are IN the
  /// room, a speaker that they are ON the mic. It used to say "المايك مفتوح"
  /// to everyone, including people with no microphone open at all.
  Future<void> start({String? roomName, bool onMic = false}) async {
    if (!_supported) return;

    // A1 — Android 13+ will not SHOW a foreground service's notification
    // without this, and several OEM builds then treat the service as
    // notification-less and reap it. Declared in the manifest since the
    // service shipped; never requested, so it was never granted. Asked for
    // here rather than at launch: this is the moment it is actually needed,
    // and a refusal costs nothing — the service still starts, exactly as it
    // did before.
    try {
      if (await Permission.notification.isDenied) {
        await PermissionGate.request(Permission.notification);
      }
    } catch (e) {
      debugPrint('[RoomAudioKeepAlive] notification permission check failed: $e');
    }

    // The service declares FOREGROUND_SERVICE_TYPE_MICROPHONE, and from
    // Android 14 starting one of those without RECORD_AUDIO is a SecurityException
    // thrown inside the SERVICE — which crashes the app rather than failing the
    // channel call. A user who declined the microphone simply keeps the
    // behaviour they had before this existed.
    try {
      if (!await Permission.microphone.isGranted) {
        debugPrint('[RoomAudioKeepAlive] microphone not granted; not starting');
        return;
      }
    } catch (e) {
      debugPrint('[RoomAudioKeepAlive] microphone check failed: $e');
      return;
    }

    try {
      await _channel.invokeMethod<bool>('start', {'roomName': roomName, 'onMic': onMic});
      _running = true;
    } on PlatformException catch (e) {
      // A device that refuses the service (notifications denied, OEM policy)
      // still works exactly as it did before this feature existed — audio cuts
      // out in the background. Never let it break taking a seat.
      debugPrint('[RoomAudioKeepAlive] start failed: ${e.message}');
    } on MissingPluginException {
      // Older host build without the channel; nothing to do.
      debugPrint('[RoomAudioKeepAlive] channel unavailable on this build');
    }
  }

  /// Call when the user leaves the seat, leaves the room, or logs out. The
  /// notification must not outlive the reason for it.
  Future<void> stop() async {
    if (!_supported || !_running) return;
    try {
      await _channel.invokeMethod<bool>('stop');
    } on PlatformException catch (e) {
      debugPrint('[RoomAudioKeepAlive] stop failed: ${e.message}');
    } on MissingPluginException {
      // Nothing was started, so nothing to stop.
    } finally {
      _running = false;
    }
  }
}
