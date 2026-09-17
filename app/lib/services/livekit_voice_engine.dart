import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_route.dart';
import 'crash_reporter.dart';
import 'dio_client.dart';
import 'socket_service.dart';
import 'voice_engine.dart';

/// The SFU engine: one connection per phone, to a LiveKit server that forwards
/// everyone's audio.
///
/// This replaces the full mesh in [WebRTCAudioService] without changing the
/// room. Everything the room sees — seats, the voice-users list, the speaking
/// ring — still comes from the SamaFox socket exactly as before; only the
/// AUDIO moves through LiveKit. So `user_joined_voice` / `user_left_voice` are
/// still emitted (the server keeps its voice set, the room keeps its list), and
/// the server-side seat rules are untouched.
///
/// What is different, and why it matters:
///
///  * A phone holds **one** peer connection whatever the room size. The mesh
///    held N−1, and uploaded N−1 copies of the microphone. That ceiling — six
///    to eight people on mobile data — is gone.
///  * Reachability is one question (can this phone reach the server?) instead
///    of N−1 questions (can it reach every other phone?). Two users behind
///    carrier-grade NAT never had a direct path; they both reach the server.
///  * Reconnection is the SDK's job. It resumes the session on a network change
///    rather than tearing down a mesh and rebuilding it from signalling.
///
/// The microphone is captured only while the user holds a seat ([goLive]) and
/// released completely on [goListenOnly], exactly as the mesh engine did after
/// A2 — no seat, no open microphone.
class LiveKitVoiceEngine implements VoiceEngine {
  static final LiveKitVoiceEngine _instance = LiveKitVoiceEngine._();
  factory LiveKitVoiceEngine() => _instance;
  LiveKitVoiceEngine._();

  void _log(String msg) => debugPrint('🎤 LK | $msg');

  final SocketService _socketService = SocketService();

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  int? _currentRoomId;
  int? _currentUserId;
  bool _initialized = false;
  bool _listenOnly = true;
  bool _isMicMuted = true;

  /// Serialises [initialize], as the mesh engine does: two overlapping calls
  /// (re-entering a room quickly) must not connect twice.
  Future<void>? _initInFlight;

  double _remoteVolume = 1.0;
  bool _noiseSuppression = true;
  static const String _kNoiseSuppressionKey = 'mic_noise_suppression';

  @override
  Function(bool isSpeaking)? onVoiceActivityChanged;
  @override
  Function(List<int> users)? onVoiceUsersUpdated;
  @override
  Function(int userId)? onPeerUnreachable;

  // ── lifecycle ────────────────────────────────────────────────────────────

  @override
  Future<void> initialize({
    required int roomId,
    required int userId,
    bool listenOnly = false,
  }) async {
    final pending = _initInFlight;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    final run = _initializeInner(roomId: roomId, userId: userId, listenOnly: listenOnly);
    _initInFlight = run;
    try {
      await run;
    } finally {
      if (identical(_initInFlight, run)) _initInFlight = null;
    }
  }

  Future<void> _initializeInner({
    required int roomId,
    required int userId,
    required bool listenOnly,
  }) async {
    _log('initialize room=$roomId user=$userId listenOnly=$listenOnly');

    // One room at a time — same rule as the mesh engine.
    if (_initialized && _currentRoomId != null && _currentRoomId != roomId) {
      _log('switching rooms: leaving $_currentRoomId first');
      await leaveVoice();
    }

    if (_initialized && _currentRoomId == roomId && _room != null) {
      if (!listenOnly && _listenOnly) await goLive();
      _log('initialize skipped (already connected)');
      return;
    }

    _currentRoomId = roomId;
    _currentUserId = userId;
    _listenOnly = listenOnly;

    await _socketService.waitUntilConnected();

    // Same announcements the mesh engine makes: the server's voice set and the
    // room's "who is in voice" list are fed by these, not by LiveKit.
    _socketService.emit('user_joined_voice', {'roomId': roomId, 'userId': userId});
    _socketService.emit('get_voice_users', {'roomId': roomId});
    _bindVoiceUsers();

    await _connect(roomId);
    _initialized = true;
    CrashReporter.breadcrumb('voice init room=$roomId listenOnly=$listenOnly engine=livekit');

    if (!listenOnly) {
      await goLive();
    } else {
      await reapplyAudioRoute();
    }
  }

  /// Fetch a token for [roomId] and connect. Throws on failure so the caller
  /// knows the room has no audio, rather than pretending.
  Future<void> _connect(int roomId) async {
    final resp = await DioClient.dio.post('/voice/token', data: {'roomId': roomId});
    final data = resp.data;
    if (data is! Map || data['success'] != true) {
      throw StateError('voice token refused: $data');
    }
    final url = data['url'].toString();
    final token = data['token'].toString();

    final room = Room(
      roomOptions: const RoomOptions(
        // Audio only, and the mic is released on unpublish (goListenOnly).
        stopLocalTrackOnUnpublish: true,
        defaultAudioPublishOptions: AudioPublishOptions(dtx: true),
      ),
    );
    final listener = room.createListener();
    _wireEvents(listener);

    await room.connect(url, token);
    _room = room;
    _listener = listener;
    _log('connected to $url as $_currentUserId (${room.remoteParticipants.length} others)');

    // Every remote track that arrives is played out; apply the room's volume
    // to the ones already there.
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.audioTrackPublications) {
        final t = pub.track;
        if (t != null) unawaited(_applyVolume(t));
      }
    }
  }

  void _wireEvents(EventsListener<RoomEvent> listener) {
    listener
      ..on<TrackSubscribedEvent>((e) {
        _log('subscribed to ${e.participant.identity}');
        unawaited(_applyVolume(e.track));
      })
      ..on<ParticipantConnectedEvent>((e) {
        CrashReporter.breadcrumb('lk +${e.participant.identity}');
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        CrashReporter.breadcrumb('lk -${e.participant.identity}');
      })
      ..on<ActiveSpeakersChangedEvent>((e) {
        final me = _currentUserId?.toString();
        final speaking = e.speakers.any((p) => p.identity == me);
        _emitSpeaking(speaking && !_isMicMuted);
      })
      ..on<RoomReconnectingEvent>((_) {
        _log('reconnecting…');
        CrashReporter.breadcrumb('lk reconnecting');
      })
      ..on<RoomReconnectedEvent>((_) {
        _log('reconnected');
        CrashReporter.breadcrumb('lk reconnected');
        unawaited(reapplyAudioRoute());
      })
      ..on<RoomDisconnectedEvent>((e) {
        _log('disconnected: ${e.reason}');
        CrashReporter.breadcrumb('lk disconnected ${e.reason}');
        _emitSpeaking(false);
        // A disconnect the SDK could not recover from, while we still believe
        // we are in the room: reconnect from scratch, with a fresh token.
        if (_initialized && _currentRoomId != null) {
          unawaited(_reconnectAfter(const Duration(seconds: 2)));
        }
      });
  }

  bool _reconnecting = false;
  Future<void> _reconnectAfter(Duration delay) async {
    if (_reconnecting) return;
    _reconnecting = true;
    try {
      await Future<void>.delayed(delay);
      final roomId = _currentRoomId;
      if (!_initialized || roomId == null) return;
      final wasLive = !_listenOnly;
      await _teardownRoom();
      await _connect(roomId);
      if (wasLive) await goLive(muted: _isMicMuted);
      _log('reconnected from scratch');
    } catch (e) {
      _log('reconnect failed: $e');
      // Try again; the SFU being briefly unreachable is the common case.
      _reconnecting = false;
      if (_initialized) unawaited(_reconnectAfter(const Duration(seconds: 5)));
      return;
    } finally {
      _reconnecting = false;
    }
  }

  /// The room's own voice list still comes from the SamaFox socket, so the UI
  /// (and the seat logic) see exactly what they saw with the mesh.
  void _bindVoiceUsers() {
    _socketService.off('voice_users', _onVoiceUsers);
    _socketService.on('voice_users', _onVoiceUsers);
  }

  void _onVoiceUsers(dynamic data) {
    try {
      final map = Map<String, dynamic>.from(data as Map? ?? {});
      final rawUsers = (map['users'] as List?) ?? const [];
      final users = rawUsers
          .map((e) => int.tryParse('$e') ?? 0)
          .where((id) => id != 0 && id != _currentUserId)
          .toList();
      onVoiceUsersUpdated?.call(users);
    } catch (e) {
      _log('voice_users parse failed: $e');
    }
  }

  Future<void> _teardownRoom() async {
    final listener = _listener;
    final room = _room;
    _listener = null;
    _room = null;
    try {
      await listener?.dispose();
    } catch (_) {}
    try {
      await room?.disconnect();
    } catch (_) {}
    try {
      await room?.dispose();
    } catch (_) {}
  }

  @override
  Future<void> leaveVoice() async {
    _log('leaveVoice room=$_currentRoomId');
    if (_currentRoomId != null && _currentUserId != null) {
      _socketService.emit('user_left_voice', {
        'roomId': _currentRoomId,
        'userId': _currentUserId,
      });
    }
    _initialized = false;
    _socketService.off('voice_users', _onVoiceUsers);
    await _teardownRoom();
    _emitSpeaking(false);
    _listenOnly = true;
    _isMicMuted = true;
    _currentRoomId = null;
    _currentUserId = null;
    CrashReporter.breadcrumb('voice left (livekit)');
  }

  @override
  Future<void> dispose() async {
    _vadEnabled = false;
    await leaveVoice();
  }

  // ── microphone ───────────────────────────────────────────────────────────

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final res = await Permission.microphone.request();
    return res.isGranted;
  }

  AudioCaptureOptions get _captureOptions => AudioCaptureOptions(
        noiseSuppression: _noiseSuppression,
        echoCancellation: true,
        autoGainControl: true,
      );

  @override
  Future<void> goLive({bool muted = false}) async {
    final lp = _room?.localParticipant;
    if (lp == null) {
      _log('goLive: not connected');
      return;
    }
    if (!await _ensureMicPermission()) {
      _log('goLive: microphone permission denied');
      return;
    }
    _listenOnly = false;
    try {
      // Captures and publishes. Idempotent when already publishing.
      await lp.setMicrophoneEnabled(true, audioCaptureOptions: _captureOptions);
      if (muted) {
        await muteAudio();
      } else {
        await unmuteAudio();
      }
      await reapplyAudioRoute();
      CrashReporter.breadcrumb('lk mic published muted=$muted');
      _log('goLive -> ${muted ? 'muted' : 'speaking'}');
    } catch (e) {
      _log('goLive failed: $e');
    }
  }

  @override
  Future<void> goListenOnly() async {
    _listenOnly = true;
    _isMicMuted = true;
    _emitSpeaking(false);
    final lp = _room?.localParticipant;
    if (lp == null) return;
    try {
      // stopLocalTrackOnUnpublish is on: this stops the capture too, so no
      // microphone stays open for a user who is not on a seat.
      await lp.unpublishAllTracks();
      CrashReporter.breadcrumb('lk mic released');
      _log('goListenOnly -> receive only');
    } catch (e) {
      _log('goListenOnly failed: $e');
    }
  }

  LocalTrackPublication<LocalAudioTrack>? get _micPublication {
    final pubs = _room?.localParticipant?.audioTrackPublications;
    if (pubs == null || pubs.isEmpty) return null;
    return pubs.first;
  }

  @override
  Future<void> muteAudio() async {
    _isMicMuted = true;
    _emitSpeaking(false);
    try {
      // stopOnMute: false keeps the capture warm so unmute is instant; the
      // seat is still held, so keeping the microphone is the intended state.
      await _micPublication?.mute(stopOnMute: false);
    } catch (e) {
      _log('mute failed: $e');
    }
  }

  @override
  Future<void> unmuteAudio() async {
    if (_listenOnly) return; // no seat, nothing to open
    _isMicMuted = false;
    try {
      final pub = _micPublication;
      if (pub == null) {
        // Nothing published (an interruption dropped it): publish again.
        await _room?.localParticipant
            ?.setMicrophoneEnabled(true, audioCaptureOptions: _captureOptions);
      } else {
        await pub.unmute(stopOnMute: false);
      }
    } catch (e) {
      _log('unmute failed: $e');
    }
  }

  @override
  Future<void> toggleMute() => _isMicMuted ? unmuteAudio() : muteAudio();

  @override
  bool get isMicMuted => _isMicMuted;

  @override
  bool get micHealthy {
    if (_listenOnly) return _room != null;
    final track = _micPublication?.track;
    return track != null && track.isActive;
  }

  @override
  Future<void> ensureMicAlive() async {
    if (!_initialized || _listenOnly) {
      await reapplyAudioRoute();
      return;
    }
    if (micHealthy) {
      await reapplyAudioRoute();
      return;
    }
    _log('mic not healthy — re-publishing');
    CrashReporter.breadcrumb('lk mic re-publish');
    await goLive(muted: _isMicMuted);
  }

  // ── output ───────────────────────────────────────────────────────────────

  @override
  Future<void> setSpeakerphoneOn(bool on) async {
    AudioRoute.instance.speakerOn = on;
    unawaited(AudioRoute.instance.apply());
    await reapplyAudioRoute();
  }

  @override
  Future<void> reapplyAudioRoute() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      await Hardware.instance.setSpeakerphoneOn(AudioRoute.instance.speakerOn);
    } catch (e) {
      _log('route apply failed: $e');
    }
  }

  @override
  Future<void> setRemoteVolume(double volume) async {
    _remoteVolume = volume.clamp(0.0, 1.0);
    final room = _room;
    if (room == null) return;
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.audioTrackPublications) {
        final t = pub.track;
        if (t != null) await _applyVolume(t);
      }
    }
  }

  Future<void> _applyVolume(Track track) async {
    try {
      final mst = track.mediaStreamTrack;
      // A slider at zero silences the room; the track itself is disabled so a
      // newly arrived speaker is not audible for a moment before the volume
      // lands — same rule the mesh engine had (A24).
      mst.enabled = _remoteVolume > 0;
      await rtc.Helper.setVolume(_remoteVolume, mst);
    } catch (e) {
      _log('volume apply failed: $e');
    }
  }

  // ── preferences ──────────────────────────────────────────────────────────

  @override
  Future<void> restorePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _noiseSuppression = prefs.getBool(_kNoiseSuppressionKey) ?? _noiseSuppression;
    } catch (e) {
      _log('preference load failed: $e');
    }
  }

  @override
  bool get noiseSuppression => _noiseSuppression;

  @override
  Future<void> setNoiseSuppression(bool enabled) async {
    if (_noiseSuppression == enabled) return;
    _noiseSuppression = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kNoiseSuppressionKey, enabled);
    } catch (_) {}
    // Capture-time constraint: re-publish for it to take effect.
    if (_initialized && !_listenOnly) {
      final muted = _isMicMuted;
      await goListenOnly();
      _listenOnly = false;
      await goLive(muted: muted);
    }
  }

  // ── voice activity ───────────────────────────────────────────────────────
  //
  // LiveKit reports active speakers itself (ActiveSpeakersChangedEvent), so
  // there is no polling here. "Enabled" only gates whether the room is told.

  bool _vadEnabled = false;
  bool _vadSpeaking = false;

  @override
  void enableVAD() => _vadEnabled = true;

  @override
  void disableVAD() {
    _vadEnabled = false;
    _emitSpeaking(false);
  }

  void _emitSpeaking(bool speaking) {
    if (!_vadEnabled && speaking) return;
    if (_vadSpeaking == speaking) return;
    _vadSpeaking = speaking;
    onVoiceActivityChanged?.call(speaking);
  }
}
