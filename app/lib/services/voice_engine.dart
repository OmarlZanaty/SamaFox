import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crash_reporter.dart';
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

  /// The engine of the room currently open (or, before any room, the one the
  /// server selects by default). The PiP bubble and the volume sheet reach the
  /// live session through this; a room screen picks its own with [forRoom].
  static VoiceEngine get instance =>
      _resolved ??= _engineFor(VoiceEngineConfig.useLiveKit);

  /// The engine for [roomId], per the server's per-room rule
  /// ([VoiceEngineConfig.useLiveKitFor]). Both engines are singletons with
  /// live state; a room is entered on ONE of them and keeps it until it is
  /// left (the choice is made once, here, when the screen is created). The
  /// previous room has already been left through [ActiveRoom] by the time the
  /// next screen calls this, so nothing is torn down here.
  static VoiceEngine forRoom(int roomId) {
    final engine = _engineFor(VoiceEngineConfig.useLiveKitFor(roomId));
    _resolved = engine;
    final name = engine is LiveKitVoiceEngine ? 'livekit' : 'mesh';
    debugPrint('🎚️ voice engine for room $roomId: $name');
    CrashReporter.breadcrumb('voice engine $name room=$roomId');
    return engine;
  }

  static VoiceEngine _engineFor(bool liveKit) =>
      liveKit ? LiveKitVoiceEngine() : WebRTCAudioService();

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
  static const String _kLkRooms = 'voice_livekit_rooms';
  static const String _kMeshRooms = 'voice_mesh_rooms';
  static const String _kTurnUrls = 'voice_turn_urls';
  static const String _kTurnUser = 'voice_turn_username';
  static const String _kTurnCred = 'voice_turn_credential';

  static String engine = 'mesh';
  static String livekitUrl = '';

  /// TURN for the mesh engine, as published by the server. Empty = use the
  /// values compiled into this build ([AppConfig.turnUrls]). Exists so that
  /// moving coturn to another box is a settings row, not an app release: the
  /// 2026-09-19 server move left every installed phone relaying through a
  /// coturn that no longer existed.
  static String turnUrls = '';
  static String turnUsername = '';
  static String turnCredential = '';

  /// Rooms that use the SFU while the default is the mesh, and the reverse.
  /// The two engines cannot hear each other, so a room moves as a whole: the
  /// admin lists it here and everyone entering it from then on lands on the
  /// same engine. Rooms are moved one at a time this way, and the default is
  /// flipped only when the last one has moved.
  static Set<int> livekitRooms = const {};
  static Set<int> meshRooms = const {};

  static bool get useLiveKit => engine == 'livekit' && livekitUrl.isNotEmpty;

  /// The rule the server applies in /voice/token as well, kept identical.
  static bool useLiveKitFor(int roomId) {
    if (livekitUrl.isEmpty) return false;
    if (livekitRooms.contains(roomId)) return true;
    if (meshRooms.contains(roomId)) return false;
    return engine == 'livekit';
  }

  static Set<int> _parseIds(dynamic raw) {
    final items = raw is List ? raw : '$raw'.split(RegExp(r'[,\s]+'));
    return items
        .map((e) => int.tryParse('$e'.trim()) ?? 0)
        .where((id) => id > 0)
        .toSet();
  }

  /// Restore the cached choice, then refresh it from the server in the
  /// background. Never throws, never blocks on the network.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      engine = prefs.getString(_kEngine) ?? engine;
      livekitUrl = prefs.getString(_kUrl) ?? livekitUrl;
      livekitRooms = _parseIds(prefs.getString(_kLkRooms) ?? '');
      meshRooms = _parseIds(prefs.getString(_kMeshRooms) ?? '');
      turnUrls = prefs.getString(_kTurnUrls) ?? turnUrls;
      turnUsername = prefs.getString(_kTurnUser) ?? turnUsername;
      turnCredential = prefs.getString(_kTurnCred) ?? turnCredential;
    } catch (_) {}
    refresh(); // not awaited — see the class doc
  }

  /// Pull the current selection from the server. Called at launch, when the
  /// app returns to the foreground, and right before a room is entered — a
  /// room the admin moved to the other engine must not be entered on a cached
  /// value from this morning. Never throws; on failure the cache stands.
  static Future<void> refresh({Duration timeout = const Duration(seconds: 4)}) async {
    try {
      final resp = await DioClient.dio
          .get('/settings')
          .timeout(timeout);
      final data = resp.data is Map ? resp.data['data'] : null;
      if (data is! Map) return;
      final e = (data['voiceEngine'] ?? 'mesh').toString();
      final u = (data['livekitUrl'] ?? '').toString().trim();
      // Only takes effect for rooms entered AFTER this point; the engine in use
      // is pinned for the process (see VoiceEngine.instance).
      engine = e;
      livekitUrl = u;
      livekitRooms = _parseIds(data['livekitRooms'] ?? '');
      meshRooms = _parseIds(data['meshRooms'] ?? '');
      final tu = (data['turnUrls'] ?? '').toString().trim();
      final tn = (data['turnUsername'] ?? '').toString().trim();
      final tc = (data['turnCredential'] ?? '').toString().trim();
      // TURN is read per peer connection, so unlike the engine it takes
      // effect on the next connection built, even inside the current room.
      turnUrls = tu;
      turnUsername = tn;
      turnCredential = tc;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kEngine, e);
      await prefs.setString(_kUrl, u);
      await prefs.setString(_kLkRooms, livekitRooms.join(','));
      await prefs.setString(_kMeshRooms, meshRooms.join(','));
      await prefs.setString(_kTurnUrls, tu);
      await prefs.setString(_kTurnUser, tn);
      await prefs.setString(_kTurnCred, tc);
      debugPrint('🎚️ voice engine setting: $e ${u.isEmpty ? '' : u}'
          ' livekitRooms=$livekitRooms meshRooms=$meshRooms'
          '${tu.isEmpty ? '' : ' turn=$tu'}');
    } catch (e) {
      debugPrint('[VoiceEngineConfig] refresh skipped: $e');
    }
  }
}
