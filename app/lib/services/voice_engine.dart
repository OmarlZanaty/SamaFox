import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dio_client.dart';
import 'livekit_voice_engine.dart';
import 'webrtc_audio_service.dart';

/// What the room needs from whatever carries its audio.
///
/// Two engines implement this:
///
///  * [WebRTCAudioService] — the original **full mesh**. Every phone connects
///    directly to every other phone in the room. Simple, no server component,
///    and it collapses past a handful of participants: a room of 20 is 19
///    connections and 19 outgoing copies of the microphone on every phone.
///  * [LiveKitVoiceEngine] — an **SFU**. One connection per phone, to a server
///    that forwards the audio. The phone's cost no longer grows with the room.
///
/// The room screen talks to this interface only, and [VoiceEngine.instance]
/// hands it whichever engine the server currently selects (see
/// [VoiceEngineConfig]). Switching engines is a settings row on the server, so
/// a problem with the new one is undone without shipping an app update.
abstract class VoiceEngine {
  // ── lifecycle ────────────────────────────────────────────────────────────
  Future<void> initialize({
    required int roomId,
    required int userId,
    bool listenOnly = false,
  });
  Future<void> leaveVoice();
  Future<void> dispose();

  // ── microphone ───────────────────────────────────────────────────────────
  /// Start transmitting (the user took a seat). [muted] = the seat's state.
  Future<void> goLive({bool muted = false});

  /// Stop transmitting and release the microphone (the user left the seat).
  Future<void> goListenOnly();

  Future<void> muteAudio();
  Future<void> unmuteAudio();
  Future<void> toggleMute();
  bool get isMicMuted;
  bool get micHealthy;

  /// Re-acquire the microphone if an interruption killed it. No-op when fine.
  Future<void> ensureMicAlive();

  // ── output ───────────────────────────────────────────────────────────────
  Future<void> setSpeakerphoneOn(bool on);
  Future<void> reapplyAudioRoute();
  Future<void> setRemoteVolume(double volume);

  // ── preferences ──────────────────────────────────────────────────────────
  Future<void> restorePreferences();
  bool get noiseSuppression;
  Future<void> setNoiseSuppression(bool enabled);

  // ── voice activity ───────────────────────────────────────────────────────
  void enableVAD();
  void disableVAD();

  // ── callbacks the room wires up ──────────────────────────────────────────
  set onVoiceActivityChanged(Function(bool isSpeaking)? cb);
  set onVoiceUsersUpdated(Function(List<int> users)? cb);
  set onPeerUnreachable(Function(int userId)? cb);

  // ── the engine the room should use right now ─────────────────────────────

  /// The engine the server has selected. Resolved once per process: an engine
  /// is a singleton with live state, and a room that started on one must not
  /// be handed the other half-way through.
  static VoiceEngine get instance {
    final chosen = _resolved;
    if (chosen != null) return chosen;
    final engine = VoiceEngineConfig.useLiveKit
        ? LiveKitVoiceEngine()
        : WebRTCAudioService();
    _resolved = engine;
    debugPrint('🎚️ voice engine: ${engine.runtimeType}');
    return engine;
  }

  static VoiceEngine? _resolved;
}

/// Which engine to use, as published by the server on `/settings`.
///
/// Loaded once at launch, cached in preferences so the very next launch does
/// not depend on the network, and defaulting to the mesh so a missing or
/// unreachable setting can never leave a device without voice.
class VoiceEngineConfig {
  VoiceEngineConfig._();

  static const String _kEngine = 'voice_engine';
  static const String _kUrl = 'voice_livekit_url';

  static String engine = 'mesh';
  static String livekitUrl = '';

  static bool get useLiveKit => engine == 'livekit' && livekitUrl.isNotEmpty;

  /// Restore the cached choice, then refresh it from the server in the
  /// background. Never throws, never blocks on the network.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      engine = prefs.getString(_kEngine) ?? engine;
      livekitUrl = prefs.getString(_kUrl) ?? livekitUrl;
    } catch (_) {}
    _refresh(); // not awaited — see the class doc
  }

  static Future<void> _refresh() async {
    try {
      final resp = await DioClient.dio.get('/settings');
      final data = resp.data is Map ? resp.data['data'] : null;
      if (data is! Map) return;
      final e = (data['voiceEngine'] ?? 'mesh').toString();
      final u = (data['livekitUrl'] ?? '').toString().trim();
      // Only takes effect for rooms entered AFTER this point; the engine in use
      // is pinned for the process (see VoiceEngine.instance).
      engine = e;
      livekitUrl = u;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kEngine, e);
      await prefs.setString(_kUrl, u);
      debugPrint('🎚️ voice engine setting: $e ${u.isEmpty ? '' : u}');
    } catch (e) {
      debugPrint('[VoiceEngineConfig] refresh skipped: $e');
    }
  }
}
