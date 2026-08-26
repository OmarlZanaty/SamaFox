import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  /// Call when the user takes a mic seat. Safe to call repeatedly — starting an
  /// already-running service only refreshes its notification.
  Future<void> start({String? roomName}) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<bool>('start', {'roomName': roomName});
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
