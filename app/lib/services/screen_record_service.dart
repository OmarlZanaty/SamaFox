import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A11 — تسجيل الشاشة مع الصوت.
///
/// The client's report is that recording works but captures no sound. That is
/// not something app code can fix for the PHONE's own recorder: Android's
/// internal-audio capture is forbidden from recording streams whose usage is
/// `USAGE_VOICE_COMMUNICATION`, and WebRTC uses exactly that for the room's
/// voice. The same rule is what stops any app recording a phone call.
///
/// So the recording moves inside the app, where the MICROPHONE can be recorded
/// alongside the screen. What that actually captures:
///
///   • the user's own voice — always;
///   • everyone else in the room — when the room is on the LOUDSPEAKER, since
///     their voices leave the speaker and come back in through the mic. On the
///     earpiece they will be faint or missing, and no API can change that.
///
/// [speakerHint] exists so the UI can say this before the user records five
/// minutes of silence and reports it as a bug.
class ScreenRecordService {
  ScreenRecordService._();
  static final ScreenRecordService instance = ScreenRecordService._();

  static const MethodChannel _channel = MethodChannel('samafox/screen_record');

  bool get supported => !kIsWeb && Platform.isAndroid;

  /// What the room should tell the user before the first recording.
  static const String speakerHint =
      'التسجيل يلتقط صوتك من الميكروفون. عشان تسجّل أصوات باقي الغرفة كمان، '
      'خلّي السماعة الخارجية مفعّلة أثناء التسجيل.';

  Future<bool> get isRecording async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isRecording') ?? false;
    } on PlatformException catch (e) {
      debugPrint('[ScreenRecord] isRecording failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Raises the system consent dialog and begins recording.
  ///
  /// Returns false when the user declines — that is a normal outcome, not an
  /// error, and the caller should say nothing about it.
  Future<bool> start() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
    } on PlatformException catch (e) {
      debugPrint('[ScreenRecord] start failed: ${e.message}');
      return false;
    } on MissingPluginException {
      // Older host build without the channel.
      return false;
    }
  }

  /// Stops and returns the file path, or null if nothing usable was written
  /// (a recording ended within a moment of starting produces no frames).
  Future<String?> stop() async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<String>('stop');
    } on PlatformException catch (e) {
      debugPrint('[ScreenRecord] stop failed: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
