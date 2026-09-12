import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/app_config.dart';
import 'socket_service.dart';
import 'audio_route.dart';


/// Complete WebRTC Audio Service with Peer Connections
/// Handles voice chat between multiple users in a room
class WebRTCAudioService {
  static final WebRTCAudioService _instance = WebRTCAudioService._internal();

  factory WebRTCAudioService() {
    return _instance;
  }

  WebRTCAudioService._internal();

  void _log(String msg) {
    debugPrint('🎤 MIC_DEBUG | $msg');
  }

  Function(List<int> users)? onVoiceUsersUpdated;

  final SocketService _socketService = SocketService();

  // Local stream and peer connections
  MediaStream? _localStream;
  final Map<int, RTCPeerConnection> _peerConnections = {};
  final Map<int, MediaStream> _remoteStreams = {};
  final Map<int, RTCVideoRenderer> _remoteRenderers = {};

  // Audio renderers for remote audio
  final List<RTCVideoRenderer> _audioRenderers = [];

  // State
  bool _isMicMuted = false;
  bool _isSpeakerOn = true;
  int? _currentRoomId;
  int? _currentUserId;
  bool _initialized = false;
  StreamSubscription? _reconnectSub;

// ICE restart helpers
  final Map<int, Timer> _iceFailTimers = {};

  /// Candidates that arrived before the peer's remote description was in place.
  ///
  /// Trickle ICE starts the instant an offer is sent, while the answering side
  /// still has several awaits to go before `setRemoteDescription` lands. Adding
  /// a candidate before then throws, and the old handler swallowed that
  /// exception — so the opening candidates of every call, the host and
  /// server-reflexive ones that actually connect two phones, were dropped on
  /// the floor. Whether a peer came up at all depended on that race, which is
  /// precisely why voice worked for some clients and not others.
  final Map<int, List<RTCIceCandidate>> _pendingCandidates = {};

  /// Peers whose remote description is set, so candidates can go straight in.
  final Set<int> _remoteDescriptionSet = {};

  /// Perfect-negotiation bookkeeping: peers we are mid-offer towards, and peers
  /// whose recovery is already running — ICE state and connection state both
  /// report the same failure, and without this they would recover it twice.
  final Set<int> _makingOffer = {};
  final Set<int> _restarting = {};

  /// Consecutive recovery attempts per peer, cleared once it connects.
  final Map<int, int> _recoveryAttempts = {};

  /// True while the session was opened without a microphone.
  bool _listenOnly = false;

  /// Guards [_recoverLocalMic] against re-entry.
  bool _recoveringMic = false;

  /// A2 — تقليل الضوضاء. Was a switch in the room menu that flipped a bool in
  /// the widget and showed a toast: suppression was hardcoded ON at capture, so
  /// the control did nothing in either position and told the user it had.
  ///
  /// It is a capture-time constraint, which is why turning it off has to
  /// re-acquire the microphone — see [setNoiseSuppression]. Default true, the
  /// behaviour every existing user already has.
  bool _noiseSuppression = true;
  bool get noiseSuppression => _noiseSuppression;

  static const String _kNoiseSuppressionKey = 'mic_noise_suppression';

  /// Load the saved choice. Call before the first capture; safe to call twice.
  Future<void> restorePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _noiseSuppression = prefs.getBool(_kNoiseSuppressionKey) ?? _noiseSuppression;
    } catch (e) {
      // A preferences failure must never cost anyone their microphone.
      _log('noise-suppression preference load failed: $e');
    }
  }

  /// Turn تقليل الضوضاء on or off for real.
  ///
  /// The constraint is applied when the microphone is OPENED, so an already
  /// running capture has to be replaced. [_recoverLocalMic] is exactly that
  /// operation — re-capture, then `replaceTrack` into every live sender, which
  /// keeps the transceivers and avoids a renegotiation round-trip, so the room
  /// hears no gap. Mute state is carried across by that path.
  ///
  /// While listen-only (no seat) there is no capture to replace; the new value
  /// simply applies to the next one.
  Future<void> setNoiseSuppression(bool enabled) async {
    if (_noiseSuppression == enabled) return;
    _noiseSuppression = enabled;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kNoiseSuppressionKey, enabled);
    } catch (e) {
      _log('noise-suppression preference save failed: $e');
    }

    if (_localStream != null && !_listenOnly && _initialized) {
      await _recoverLocalMic();
    }
    _log('noiseSuppression=$enabled');
  }

  /// STUN can only introduce two peers when at least one is reachable from
  /// outside. It cannot help when both sit behind a carrier-grade NAT, the
  /// normal case for two users on mobile data, and that pair simply never
  /// connects. Configure a TURN server (see [AppConfig.turnUrls]) and it is
  /// added here automatically.
  static List<Map<String, dynamic>> get _iceServers {
    final servers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
    ];

    final turnUrls = AppConfig.turnUrls
        .split(',')
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
    if (turnUrls.isNotEmpty) {
      servers.add(<String, dynamic>{
        'urls': turnUrls,
        if (AppConfig.turnUsername.isNotEmpty) 'username': AppConfig.turnUsername,
        if (AppConfig.turnCredential.isNotEmpty)
          'credential': AppConfig.turnCredential,
      });
    }
    return servers;
  }

  /// Only one side may drive a rebuild, otherwise both tear down at once and
  /// the replacement offer lands on a peer that is still disposing of the old
  /// connection. The initiator drives; the other side is the "polite" peer and
  /// yields on a collision.
  bool _isPolite(int otherUserId) => !_shouldInitiateWith(otherUserId);

  /// Ids cross the socket as ints today and as strings on some server builds;
  /// a hard cast turns that into a thrown handler and a dead peer.
  static int? _asUserId(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw');
  }

  // Voice Activity Detection (VAD) — A10 "المتكلم على المايك يظهر حوله دائرة
  // متحركة ... واذا سكت تختفي الدائرة".
  //
  // The level is read from the peer connection's `media-source` stats, which is
  // the ONLY local audio level flutter_webrtc exposes. It used to be read from
  // `_audioLevel`, a field nothing ever wrote, so the detector saw permanent
  // silence: the ring never appeared and the old auto-mute branch below kept
  // closing the user's mic. Both are fixed here.
  Timer? _vadTimer;
  double _audioLevel = 0.0;
  bool _vadEnabled = false;
  /// Last state handed to [onVoiceActivityChanged]; transitions only.
  bool _vadSpeaking = false;
  /// Consecutive quiet ticks before the ring is taken down. At 200ms a tick
  /// that is ~600ms, short enough to track speech, long enough not to strobe
  /// between syllables.
  int _vadQuietTicks = 0;
  static const int _vadQuietTicksToStop = 3;
  /// `audioLevel` is 0..1 RMS. Normal speech on a phone sits well above 0.02;
  /// room noise and breathing sit below it.
  static const double _vadSpeakingLevel = 0.02;
  static const Duration _vadInterval = Duration(milliseconds: 200);
  MediaStreamTrack? _localAudioTrack;

  bool _localMuted = true;
  // Push-to-Talk (PTT) mode
  bool _pttMode = false;
  bool _isPttActive = false;

  // Callbacks
  Function(int userId, MediaStream stream)? onRemoteStreamAdded;
  Function(int userId)? onRemoteStreamRemoved;
  Function(String message)? onError;
  Function(bool isSpeaking)? onVoiceActivityChanged;

  Future<void> _ensureLocalStream() async {
    if (_localStream != null && _localAudioTrack != null) return;
    await _captureLocalStream();
  }

  /// The one place the microphone is opened. `initialize` used to carry its own
  /// copy of this with a different constraint set, so a stream acquired
  /// anywhere else came up without the echo canceller.
  Future<void> _captureLocalStream() async {
    // A2 — only the NOISE keys follow the toggle. Echo cancellation and
    // auto-gain stay on whatever the user picks: switching those off in a
    // speakerphone room feeds the loudspeaker straight back into the mic, and
    // "تقليل الضوضاء" is not a request for howling.
    final ns = _noiseSuppression;
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': ns,
        'autoGainControl': true,

        // WebRTC Android legacy keys (plugin prints these)
        'googEchoCancellation': true,
        'googEchoCancellation2': true,
        'googDAEchoCancellation': true,
        'googNoiseSuppression': ns,
        'googAutoGainControl': true,
        // The highpass filter is part of the same noise chain — it is what
        // removes rumble and handling noise, so it follows the switch too.
        'googHighpassFilter': ns,

        // Helpful constraints
        'channelCount': 1,
      },
      'video': false,
    });

    _localStream = stream;

    final tracks = stream.getAudioTracks();
    _localAudioTrack = tracks.isNotEmpty ? tracks.first : null;

    _log('Local stream created. audioTracks=${tracks.length}');
    if (_localAudioTrack == null) {
      _log('❌ No audio track found (getUserMedia returned none)');
    } else {
      _localAudioTrack!.enabled = true;
      _watchLocalTrack(_localAudioTrack!);
      _log('Track enabled=${_localAudioTrack!.enabled}');
    }
  }

  /// A local microphone track can die without the app noticing: an incoming
  /// phone call, another app claiming the mic, or the OS reclaiming capture all
  /// end it. WebRTC keeps sending the now-silent stream, so the seat still
  /// looks live while nobody can hear the user — the report that the mic "cuts
  /// out" and only a full rejoin brings it back. Re-acquire instead.
  void _watchLocalTrack(MediaStreamTrack track) {
    track.onEnded = () {
      _log('🎤 local track ended — re-acquiring the microphone');
      unawaited(_recoverLocalMic());
    };
    track.onMute = () => _log('🎤 local track muted by the platform');
    track.onUnMute = () => _log('🎤 local track un-muted by the platform');
  }

  /// Stop watching a track we are about to stop ourselves. Without this,
  /// leaving the room ends the track, the watchdog reads that as the mic being
  /// snatched away, and re-opens the microphone of a user who just left.
  void _detachTrackWatch(MediaStreamTrack track) {
    track.onEnded = null;
    track.onMute = null;
    track.onUnMute = null;
  }

  Future<void> _recoverLocalMic() async {
    if (_recoveringMic || _listenOnly || !_initialized) return;
    _recoveringMic = true;
    try {
      final wasMuted = _isMicMuted;

      final old = _localStream;
      _localStream = null;
      _localAudioTrack = null;
      if (old != null) {
        for (final t in old.getTracks()) {
          _detachTrackWatch(t);
          try {
            await t.stop();
          } catch (_) {}
        }
      }

      await _captureLocalStream();
      final track = _localAudioTrack;
      if (track == null) {
        _log('❌ mic recovery: no track after re-capture');
        return;
      }
      track.enabled = !wasMuted;

      // Swap the new track into every live sender. `replaceTrack` does this in
      // place, so the peers keep their transceivers and no renegotiation
      // round-trip (and no audible gap) is needed.
      for (final entry in _peerConnections.entries) {
        try {
          final senders = await entry.value.getSenders();
          for (final sender in senders) {
            if (sender.track?.kind == 'audio') {
              await sender.replaceTrack(track);
            }
          }
        } catch (e) {
          _log('⚠️ replaceTrack for ${entry.key} failed: $e');
        }
      }
      _log('✅ microphone re-acquired');
    } catch (e) {
      _log('❌ mic recovery failed: $e');
    } finally {
      _recoveringMic = false;
    }
  }

  /// Step 5: mic is "perfect" when we have a live local audio track. It is
  /// captured with echo-cancellation and auto-gain always on; noise
  /// suppression follows the user's own تقليل الضوضاء switch, and turning that
  /// off is a deliberate choice rather than an unhealthy microphone.
  bool get micHealthy => _localStream != null && _localAudioTrack != null;

  Future<void> setLocalMuted(bool muted) async {
    _localMuted = muted;
    await _ensureLocalStream();

    if (_localAudioTrack == null) return;

    // This is the REAL mic mute switch
    _localAudioTrack!.enabled = !muted;
    _log('🎤 setLocalMuted($muted) => track.enabled=${_localAudioTrack!.enabled}');

    // Optional: also tell Android audio system
    try {
      // If you use Helper from flutter_webrtc:
      // await Helper.setMicrophoneMute(muted);
    } catch (_) {}
  }

  bool get isLocalMuted => _localMuted;

  Future<void> _ensureMicReady() async {
    final status = await Permission.microphone.status;
    _log('Mic permission: $status');

    if (!status.isGranted) {
      final res = await Permission.microphone.request();
      _log('Mic permission request result: $res');
    }

    if (!kIsWeb && Platform.isAndroid) {
      await _forceAndroidVoiceRoute();
    }

  }

  Future<void> _attachLocalTrackToAllPeers() async {
    if (_localStream == null) return;

    final track = _localAudioTrack ??
        (_localStream!.getAudioTracks().isNotEmpty
            ? _localStream!.getAudioTracks().first
            : null);
    if (track == null) return;

    for (final pc in _peerConnections.values) {
      final senders = await pc.getSenders();
      final alreadyHasAudio = senders.any((s) => s.track?.kind == 'audio');
      if (alreadyHasAudio) continue;

      try {
        await pc.addTrack(track, _localStream!);
        _log('🎙️ Added mic track to existing PC');
      } catch (e) {
        _log('⚠️ addTrack to existing PC failed: $e');
      }
    }
  }

  /// Make sure this client actually has a microphone to send, and that every
  /// peer is carrying it.
  ///
  /// A session opened listen-only has no local stream at all: its peers were
  /// negotiated receive-only and `unmuteAudio` had nothing to enable. Someone
  /// who joined as a listener and was then approved for a mic therefore stayed
  /// silent for the whole room while their own UI showed them live.
  Future<void> _ensureSpeakingStream() async {
    _listenOnly = false;
    if (_localStream == null || _localAudioTrack == null) {
      await _ensureMicReady();
      await _captureLocalStream();
    }
    await _attachLocalTrackToAllPeers();
    await _renegotiateAllPeers();
  }

  Future<void> _renegotiateAllPeers() async {
    // Snapshot: sending an offer can end up rebuilding a peer, and mutating the
    // map while iterating it throws.
    for (final otherUserId in _peerConnections.keys.toList()) {
      await _sendOffer(otherUserId);
    }
  }

  /// The plugin's own default offer constraints, spelled out because this
  /// interface version types the parameter non-nullable — "use the default"
  /// cannot be said with `null` — and because the ice-restart variant below has
  /// to keep everything else about the offer identical.
  static const Map<String, dynamic> _defaultOfferConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': true,
    },
    'optional': <dynamic>[],
  };

  /// `IceRestart` is libwebrtc's legacy mandatory-constraint spelling, which is
  /// what the Android and iOS bridges parse. [RTCPeerConnection.restartIce]
  /// already arms the flag natively; this is the fallback for a platform where
  /// that call does nothing.
  static const Map<String, dynamic> _iceRestartOfferConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': true,
      'IceRestart': true,
    },
    'optional': <dynamic>[],
  };

  /// Create and send an offer to one peer, with the glare bookkeeping the
  /// receiving side relies on to resolve a collision.
  Future<void> _sendOffer(int otherUserId, {bool iceRestart = false}) async {
    final pc = _peerConnections[otherUserId];
    if (pc == null) return;
    if (_makingOffer.contains(otherUserId)) {
      _log('⏭️ offer to $otherUserId already in flight');
      return;
    }

    _makingOffer.add(otherUserId);
    try {
      final offer = await pc.createOffer(
        iceRestart ? _iceRestartOfferConstraints : _defaultOfferConstraints,
      );
      await pc.setLocalDescription(offer);

      _socketService.emit('webrtc_offer', {
        'roomId': _currentRoomId,
        'to': otherUserId,
        'from': _currentUserId,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
      });

      _log('📤 Offer sent to $otherUserId (iceRestart=$iceRestart)');
    } catch (e) {
      _log('⚠️ offer to $otherUserId failed: $e');
    } finally {
      _makingOffer.remove(otherUserId);
    }
  }

  Future<void> _forceAndroidVoiceRoute() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _applyEchoSafeMode(talking: false);
  }


  Future<void> _applyAndroidAudioRoute({required bool speakerOn}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await Helper.setSpeakerphoneOn(speakerOn);
      _log('Android route -> speakerOn=$speakerOn');
    } catch (e) {
      _log('⚠️ _applyAndroidAudioRoute failed: $e');
    }
  }

  /// Re-apply the user's chosen route.
  ///
  /// A3 — this used to ignore its argument and force `speakerOn: true` every
  /// time. It runs on mute, on unmute, on init and on every mic re-acquire, so
  /// choosing the earpiece was silently undone within seconds and the icon
  /// looked dead ("ايقونة السماعه موجوده لكن غير فعاله"). The choice lives in
  /// [AudioRoute] now, shared with the game sound effects, and this only
  /// re-asserts it.
  ///
  /// `talking` is kept in the signature because the call sites read as
  /// documentation of when the route is re-applied, but it no longer overrides
  /// the user: echo is handled by the AEC/NS processing already enabled on the
  /// capture stream, not by silently moving them to the earpiece.
  Future<void> _applyEchoSafeMode({required bool talking}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _applyAndroidAudioRoute(speakerOn: AudioRoute.instance.speakerOn);
  }


  /// Serialises [initialize]. Null when no initialization is running.
  Future<void>? _initInFlight;

  /// Initialize WebRTC for a specific room and user.
  ///
  /// Re-entrancy is the whole point of this wrapper. The "already initialized"
  /// guard inside sits AFTER two awaits (_ensureMicReady and
  /// waitUntilConnected) and `_initialized` is only set after those, so two
  /// calls landing within that window BOTH passed the guard and both built a
  /// mesh. Observed on device: two `initialize` lines 400ms apart on re-entering
  /// a room, then `Peer connection already exists`, and a published track with
  /// `Track enabled=true` but `totalSamples=0.0` — the peer was still sending
  /// the FIRST capture, which the second had already replaced and stopped. The
  /// user appeared live, on a seat, and was silent to everyone; reopening the
  /// app rejoined and raced again, which is why a restart did not help.
  ///
  /// A second caller now waits for the first to finish and then falls through
  /// to the real guard, which short-circuits (and performs the listen-only →
  /// speaking upgrade if that is what it asked for).
  Future<void> initialize({
    required int roomId,
    required int userId,
    bool listenOnly = false,
  }) async {
    final pending = _initInFlight;
    if (pending != null) {
      _log('initialize queued behind one already running');
      try {
        await pending;
      } catch (_) {
        // The first attempt's failure is its own caller's problem; this one
        // still gets a clean run below.
      }
    }

    final run = _initializeInner(
      roomId: roomId,
      userId: userId,
      listenOnly: listenOnly,
    );
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
    bool listenOnly = false,
  }) async {
    _log('initialize listenOnly=$listenOnly roomId=$roomId userId=$userId');

    _currentRoomId = roomId;        // ✅ REQUIRED
    _currentUserId = userId;        // ✅ REQUIRED

    await _ensureMicReady();

    _setupSignaling();              // ✅ REQUIRED

// 🔥 FIX 2: wait for socket before emitting ANY voice events
    await _socketService.waitUntilConnected();

    // ✅ Prevent double initialize for same room/user
    if (_initialized && _currentRoomId == roomId && _currentUserId == userId) {
      // ...except when a listen-only session now has to speak. Returning here
      // unconditionally left `_localStream` null, so the user took a mic seat
      // with nothing to send and every unmute was a silent no-op.
      if (!listenOnly && _localStream == null) {
        _log('⬆️ Upgrading listen-only session to speaking');
        await _ensureSpeakingStream();
        await _forceAndroidVoiceRoute();
      }
      _log('initialize skipped (already initialized for same room/user)');
      return;
    }
    _initialized = true;
    _listenOnly = listenOnly;

// ✅ On socket reconnect, rebuild the whole voice mesh.
    await _reconnectSub?.cancel();
    _reconnectSub = _socketService.reconnectStream.listen((_) async {
      if (_currentRoomId == null || _currentUserId == null) return;

      _log('🔁 socket reconnected -> rebuilding voice mesh');

      // Every peer connection made over the old socket is dead: its signalling
      // path is gone, so it can neither restart ICE nor renegotiate. Drop ours
      // first, then announce with `resume: true` — the server only broadcasts
      // the matching `user_left_voice` for a resume, and without it every peer
      // keeps OUR corpse, sees us "already connected" and skips rebuilding, so
      // the returning user comes back mute for the entire room.
      await _teardownAllPeers();

      _socketService.emit('user_joined_voice', {
        'roomId': _currentRoomId,
        'userId': _currentUserId,
        'resume': true,
      });
      _socketService.emit('get_voice_users', {'roomId': _currentRoomId});
    });


    if (!listenOnly) {
      await _captureLocalStream();
      await _forceAndroidVoiceRoute();
    } else {
      _localStream = null;
      _localAudioTrack = null;
      _log('Listen-only mode → no mic stream');
    }


    // ✅ Tell server you are in voice (include both roomId + userId)
    _socketService.emit('user_joined_voice', {
      'roomId': roomId,
      'userId': userId,
    });
// ✅ Make sure track is actually enabled after signaling join
    if (listenOnly) {
      await _applyEchoSafeMode(talking: false); // speaker ON
    } else {
      //await muteAudio(); // mic OFF + speaker ON
    }    _log('Post-join -> forced unmuteAudio()');


    // Optional if your server supports it:
    _socketService.emit('get_voice_users', {'roomId': roomId});

    startMicStats();
  }


  Future<void> leaveVoice() async {
    try {
      // ✅ tell server you left voice
      if (_currentRoomId != null && _currentUserId != null) {
        _socketService.emit('user_left_voice', {
          'roomId': _currentRoomId,
          'userId': _currentUserId,
        });
      }

      // stop local mic track
      _initialized = false; // before stopping, so the watchdog stays quiet
      if (_localStream != null) {
        for (final t in _localStream!.getTracks()) {
          _detachTrackWatch(t);
          try { await t.stop(); } catch (_) {}
        }
        _localStream = null;
        _localAudioTrack = null;
      }

      // close all peer connections and everything hanging off them
      await _teardownAllPeers();
      _audioRenderers.clear();

      _initialized = false;
      _listenOnly = false;
      _currentRoomId = null;
      _currentUserId = null;
    } catch (_) {}
  }


  bool _shouldInitiateWith(int otherUserId) {
    // ✅ only higher userId initiates
    final me = _currentUserId ?? 0;
    return me > otherUserId;
  }

  Timer? _statsTimer;

  void startMicStats() {
    _statsTimer?.cancel();

    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_peerConnections.isEmpty) return;

      for (final entry in _peerConnections.entries) {
        final otherUserId = entry.key;
        final pc = entry.value;

        try {
          final stats = await pc.getStats();
          for (final r in stats) {
            // Outbound RTP stats
            if (r.type == 'outbound-rtp' &&
                (r.values['kind'] == 'audio' || r.values['mediaType'] == 'audio')) {
              _log(
                'OUT AUDIO to=$otherUserId bytesSent=${r.values['bytesSent']} '
                    'packetsSent=${r.values['packetsSent']} '
                    'ssrc=${r.values['ssrc']}',
              );
            }

            // Audio source stats (tells if mic produces samples)
            if (r.type == 'media-source' && (r.values['kind'] == 'audio')) {
              _log(
                'MIC SOURCE to=$otherUserId audioLevel=${r.values['audioLevel']} '
                    'totalSamples=${r.values['totalSamplesDuration'] ?? r.values['totalSamplesReceived']}',
              );
            }
          }

        } catch (_) {
          // ignore stats errors for some connections
        }
      }
    });
  }


  /// Setup WebRTC signaling via Socket.IO
  void _setupSignaling() {
    _socketService.off('user_joined_voice');
    _socketService.off('user_left_voice');
    _socketService.off('voice_users');
    _socketService.off('webrtc_offer');
    _socketService.off('webrtc_answer');
    _socketService.off('webrtc_ice_candidate');

    // Listen for other users joining voice chat
    _socketService.on('user_joined_voice', (data) async {


      try {
        final map = Map<String, dynamic>.from(data as Map);

        final otherUserId = (map['userId'] ?? map['from'] ?? map['id']);
        final int? oid = otherUserId is int ? otherUserId : int.tryParse('$otherUserId');

        if (oid == null) {
          debugPrint('⚠️ user_joined_voice missing userId: $map');
          return;
        }

        if (oid != _currentUserId) {
          final isInitiator = _shouldInitiateWith(oid);
          debugPrint('👤 User $oid joined voice chat (initiator=$isInitiator)');
          await _createPeerConnection(oid, isInitiator: isInitiator);
        }

      } catch (e) {
        debugPrint('❌ Error handling user_joined_voice: $e');
        onError?.call('Error: $e');
      }
    });


// ✅ Receive current voice users list and connect to them
    _socketService.on('voice_users', (data) async {
      try {
        final map = Map<String, dynamic>.from(data ?? {});
        final rawUsers = (map['users'] as List?) ?? const [];

        final users = rawUsers
            .map((e) => int.tryParse('$e') ?? 0)
            .where((id) => id != 0 && id != _currentUserId)
            .toList();

        debugPrint('👥 voice_users in room $_currentRoomId: $users');

        // ✅ ADD THIS
        onVoiceUsersUpdated?.call(users);

        for (final otherUserId in users) {
          final isInitiator = _shouldInitiateWith(otherUserId);
          await _createPeerConnection(otherUserId, isInitiator: isInitiator);
        }

      } catch (e) {
        debugPrint('❌ Error handling voice_users: $e');
      }
    });

    // Listen for WebRTC offers
    _socketService.on('webrtc_offer', (data) async {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final fromUserId = _asUserId(map['from']);
        if (fromUserId == null) {
          debugPrint('⚠️ webrtc_offer without a usable sender: $map');
          return;
        }
        final offer = Map<String, dynamic>.from(map['offer'] as Map);

        debugPrint('📨 Received offer from user $fromUserId');

        final pc = await _createPeerConnection(fromUserId, isInitiator: false);

        // Perfect negotiation. Both sides can be offering at the same moment —
        // a mic approval renegotiates towards everyone while a peer is
        // recovering — and applying an offer on top of our own throws, which
        // used to kill that link permanently. The impolite peer (the initiator)
        // ignores the collision; the polite one rolls its own offer back and
        // accepts.
        final state = await pc.getSignalingState();
        final collision = _makingOffer.contains(fromUserId) ||
            state == RTCSignalingState.RTCSignalingStateHaveLocalOffer;
        var rolledBack = false;
        if (collision) {
          if (!_isPolite(fromUserId)) {
            _log('🙅 Ignoring colliding offer from $fromUserId (impolite peer)');
            return;
          }
          _log('🙇 Rolling back local offer to $fromUserId (polite peer)');
          try {
            await pc.setLocalDescription(RTCSessionDescription(null, 'rollback'));
            rolledBack = true;
          } catch (e) {
            _log('⚠️ rollback rejected by the platform: $e');
          }
        }

        // Set remote description (offer)
        await pc.setRemoteDescription(
          RTCSessionDescription(offer['sdp'] as String, offer['type'] as String),
        );
        await _flushPendingCandidates(fromUserId);

        // Create and send answer
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);

        _socketService.emit('webrtc_answer', {
          'roomId': _currentRoomId,
          'to': fromUserId,
          'from': _currentUserId,
          'answer': {
            'sdp': answer.sdp,
            'type': answer.type,
          },
        });

        debugPrint('📤 Sent answer to user $fromUserId');

        // A2 — the offer we just discarded was OURS, and it carried whatever
        // local change prompted it: on a rejoin that is the microphone track
        // goLive() had just attached. The remote's offer was built before it
        // knew about that track, so answering it settles the session WITHOUT
        // our audio in it — sender present, `packetsSent=0`, silent to the whole
        // room while the seat looks live.
        //
        // Perfect negotiation expects the polite peer to re-offer once the
        // collision is resolved; this implementation drives offers by hand, so
        // nothing did. The remote is stable now that it has our answer, so this
        // offer will not collide again.
        if (rolledBack) {
          _log('↩️ Re-offering to $fromUserId after rollback');
          unawaited(_sendOffer(fromUserId));
        }
      } catch (e) {
        debugPrint('❌ Error handling webrtc_offer: $e');
        onError?.call('Error handling offer: $e');
      }
    });

    // Listen for WebRTC answers
    _socketService.on('webrtc_answer', (data) async {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final fromUserId = _asUserId(map['from']);
        if (fromUserId == null) {
          debugPrint('⚠️ webrtc_answer without a usable sender: $map');
          return;
        }
        final answer = Map<String, dynamic>.from(map['answer'] as Map);

        debugPrint('📨 Received answer from user $fromUserId');

        final pc = _peerConnections[fromUserId];
        if (pc != null) {
          // An answer for an offer we already dropped — rolled back after a
          // collision, or superseded by a rebuild — throws on the way in and
          // takes the peer with it. Only apply one we are still waiting for.
          final state = await pc.getSignalingState();
          if (state != RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
            _log('↩️ Ignoring stale answer from $fromUserId (state=$state)');
            return;
          }
          await pc.setRemoteDescription(
            RTCSessionDescription(answer['sdp'] as String, answer['type'] as String),
          );
          await _flushPendingCandidates(fromUserId);
          debugPrint('✅ Set remote description for user $fromUserId');
        }
      } catch (e) {
        debugPrint('❌ Error handling webrtc_answer: $e');
        onError?.call('Error handling answer: $e');
      }
    });

    // Listen for ICE candidates
    _socketService.on('webrtc_ice_candidate', (data) async {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final fromUserId = _asUserId(map['from']);
        if (fromUserId == null) return;
        final raw = Map<String, dynamic>.from(map['candidate'] as Map);

        final candidate = RTCIceCandidate(
          raw['candidate'] as String?,
          raw['sdpMid'] as String?,
          raw['sdpMLineIndex'] is int
              ? raw['sdpMLineIndex'] as int
              : int.tryParse('${raw['sdpMLineIndex']}'),
        );

        final pc = _peerConnections[fromUserId];
        if (pc == null || !_remoteDescriptionSet.contains(fromUserId)) {
          // Hold it. Adding a candidate before the remote description throws
          // and the candidate is then gone for good — see [_pendingCandidates].
          // The cap keeps a peer that never completes from growing without
          // bound; ICE needs only the first handful to find a path.
          final queue = _pendingCandidates.putIfAbsent(fromUserId, () => []);
          if (queue.length < 128) queue.add(candidate);
          return;
        }

        await pc.addCandidate(candidate);
      } catch (e) {
        debugPrint('⚠️ Error adding ICE candidate: $e');
      }
    });

    // ✅ MIC APPROVED -> attach track to all peers + renegotiate
    _socketService.off('approveMic');
    _socketService.on('approveMic', (data) async {
      try {
        final map = Map<String, dynamic>.from(data ?? {});
        final int? uid = map['userId'] is int ? map['userId'] : int.tryParse('${map['userId']}');

        // لو approveMic مش بتاعتك، تجاهل
        if (uid != null && uid != _currentUserId) return;

        _log('✅ approveMic received, enabling mic & renegotiating...');

        // Capture first, then unmute: with no stream there is nothing to
        // unmute, and the peers still have to be told about the new track.
        await _ensureSpeakingStream();
        await unmuteAudio();

      } catch (e) {
        _log('❌ approveMic handler error: $e');
      }
    });


    // Listen for user leaving voice chat
    _socketService.on('user_left_voice', (data) {
      try {
        final map = Map<String, dynamic>.from(data as Map);
        final otherUserId = _asUserId(map['userId']);
        if (otherUserId == null || otherUserId == _currentUserId) return;
        debugPrint('👤 User $otherUserId left voice chat');
        _closePeerConnection(otherUserId);
      } catch (e) {
        debugPrint('❌ Error handling user_left_voice: $e');
      }
    });
  }

  /// Create a peer connection with another user
  /// Create a peer connection with another user
  Future<RTCPeerConnection> _createPeerConnection(
      int otherUserId, {
        required bool isInitiator,
      }) async {
    try {
      // Reuse a LIVE connection only. Handing back a closed or failed one is
      // how a peer stayed dead after a network blip: the offer meant to rebuild
      // it was applied to the corpse, threw, and nothing tried again.
      final existing = _peerConnections[otherUserId];
      if (existing != null) {
        if (_isPeerUsable(existing)) {
          debugPrint('⚠️ Peer connection already exists for user $otherUserId');
          // A2 — "usable" only ever meant the ICE/DTLS transport was alive, and
          // that transport SURVIVES a signalling drop: socket.io dies, the media
          // path does not. So after a reconnect this returned a peer that looked
          // perfectly healthy and was reused as-is — including when it had been
          // built during a listen-only spell and therefore carried no sender of
          // ours at all, or carried one whose track a later capture had already
          // replaced and stopped.
          //
          // On device that read as `MIC SOURCE totalSamples=null` (no sender) or
          // `OUT AUDIO bytesSent=0 packetsSent=0` (sender, dead track), with the
          // seat showing live and the room hearing nothing.
          await _ensureSenderOn(existing, otherUserId);
          return existing;
        }
        _log('♻️ Dropping dead peer connection with $otherUserId before rebuild');
        await _disposePeer(otherUserId);
      }

      debugPrint('🔗 Creating peer connection with user $otherUserId (initiator: $isInitiator)');

      // ICE servers configuration with STUN/TURN and optimizations
      final configuration = <String, dynamic>{
        'iceServers': _iceServers,
        'sdpSemantics': 'unified-plan',
        'bundlePolicy': 'max-bundle',
        'rtcpMuxPolicy': 'require',
        'iceCandidatePoolSize': 10,
      };

      // Create peer connection
      final pc = await createPeerConnection(configuration);

      // Add local audio tracks once (if we have mic). Otherwise RecvOnly.
      if (_localStream != null) {
        for (final track in _localStream!.getAudioTracks()) {
          try {
            await pc.addTrack(track, _localStream!);
          } catch (e) {
            debugPrint('⚠️ addTrack failed for user $otherUserId: $e');
          }
        }
      } else {
        await pc.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
      }

      // Optional extra configuration (may throw on some builds)
      try {
        await pc.setConfiguration({
          ...configuration,
          'audioJitterBufferMaxPackets': 50,
          'audioJitterBufferFastAccelerate': true,
        });
      } catch (e) {
        debugPrint('⚠️ Could not set extra audio configuration: $e');
      }

      // Handle remote tracks (audio)
      pc.onTrack = (RTCTrackEvent event) {
        try {
          if (event.streams.isEmpty) return;

          final remoteStream = event.streams[0];
          _remoteStreams[otherUserId] = remoteStream;

          for (final t in remoteStream.getAudioTracks()) {
            // A24 — a peer that joins while the listener has the slider at 0
            // must arrive muted. Enabling every incoming track unconditionally
            // is what made a new speaker audible again seconds after the user
            // had silenced the room.
            t.enabled = _remoteVolume > 0;
          }
          _applyVolumeToStream(remoteStream);

          _log('🔊 Remote stream added from user $otherUserId '
              'tracks=${remoteStream.getAudioTracks().length}');

          // ✅ no renderer needed for audio
          onRemoteStreamAdded?.call(otherUserId, remoteStream);
        } catch (e) {
          _log('❌ Error handling remote track: $e');
          onError?.call('Error handling remote track: $e');
        }
      };


      // ICE candidates -> send to other peer
      pc.onIceCandidate = (RTCIceCandidate candidate) {
        try {
          _socketService.emit('webrtc_ice_candidate', {
            'roomId': _currentRoomId,
            'to': otherUserId,
            'from': _currentUserId,
            'candidate': {
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            },
          });
        } catch (e) {
          debugPrint('⚠️ Failed sending ICE candidate to $otherUserId: $e');
        }
      };

      // ICE connection state changes (KEEP ONLY ONE HANDLER — the restart one)
      pc.onIceConnectionState = (RTCIceConnectionState state) {
        debugPrint('❄️ ICE connection state with user $otherUserId: $state');

        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          unawaited(_recoverPeer(otherUserId));
          return;
        }

        if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          // `disconnected` is routine on a phone: a wifi/4G handover, a lift, a
          // moment of packet loss all land here and clear themselves within
          // seconds. Rebuilding the connection at 4s turned every blip into an
          // audible drop, so give ICE room to heal on its own first.
          _iceFailTimers[otherUserId]?.cancel();
          _iceFailTimers[otherUserId] = Timer(const Duration(seconds: 8), () {
            unawaited(_recoverPeer(otherUserId));
          });
          return;
        }

        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _iceFailTimers.remove(otherUserId)?.cancel();
          _recoveryAttempts.remove(otherUserId);
        }
      };

      // Overall connection state. DTLS can fail while ICE still reports itself
      // connected, so this is a second, independent failure signal — the peer
      // is silent either way and only this one notices.
      pc.onConnectionState = (RTCPeerConnectionState state) {
        debugPrint('🔄 Connection state with user $otherUserId: $state');

        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          unawaited(_recoverPeer(otherUserId));
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _iceFailTimers.remove(otherUserId)?.cancel();
          _recoveryAttempts.remove(otherUserId);
        }
      };

      _peerConnections[otherUserId] = pc;

      // Create offer if initiator
      if (isInitiator) {
        await _sendOffer(otherUserId);
      }

      startMicStats();
      return pc;
    } catch (e) {
      debugPrint('❌ Error creating peer connection: $e');
      onError?.call('Error creating peer connection: $e');
      rethrow;
    }
  }



  /// Mute microphone
  Future<void> muteAudio() async {
    try {
      if (_localStream != null) {
        for (var track in _localStream!.getAudioTracks()) {
          track.enabled = false;
        }
        _isMicMuted = true;
        debugPrint('🔇 Microphone muted');

        // ✅ listening mode => speaker ON
        await _applyEchoSafeMode(talking: false);
      }
    } catch (e) {
      debugPrint('❌ Error muting audio: $e');
      onError?.call('Error muting audio: $e');
    }
  }

  /// A2 — go live on the mic.
  ///
  /// The room is now joined listen-only: nobody captures a microphone until
  /// they actually take a seat. Before this, EVERY member of a room opened a
  /// live capture and transmitted into a full mesh, so a 30-person room ran 30
  /// hot microphones — the "ضوضاء وصدى" report, and an upstream load no phone
  /// survives. Call this when the user takes a seat.
  Future<void> goLive() async {
    if (!_initialized) return;
    await _ensureSpeakingStream();
    await unmuteAudio();
    _log('goLive -> speaking');
  }

  /// A2 — stop transmitting, keep listening. Called when the user leaves a seat.
  Future<void> goListenOnly() async {
    if (!_initialized) return;
    await muteAudio();
    _listenOnly = true;
    _log('goListenOnly -> receive only');
  }

  Future<void> unmuteAudio() async {
    try {
      if (_localStream != null) {
        for (var track in _localStream!.getAudioTracks()) {
          track.enabled = true;
        }
        _isMicMuted = false;
        debugPrint('🔊 Microphone unmuted');

        // ✅ talking mode => speaker OFF (earpiece) to kill echo
        await _applyEchoSafeMode(talking: true);
      }
    } catch (e) {
      debugPrint('❌ Error unmuting audio: $e');
      onError?.call('Error unmuting audio: $e');
    }
  }


  /// Toggle microphone
  Future<void> toggleMute() async {
    if (_isMicMuted) {
      await unmuteAudio();
    } else {
      await muteAudio();
    }
  }

  // ============================================================
  // A24 — "مؤشر الصوت لما أنزله للصفر المفروض يقفل الصوت خالص"
  //
  // The room's volume slider only ever reached the sound-effects player and
  // the seat-video controller. The one thing it never reached was the WebRTC
  // voice, which is the only thing the user is trying to silence when they drag
  // it to zero — hence the report that it "مش بيقفل".
  //
  // Two mechanisms, deliberately both:
  //   • Helper.setVolume gives real attenuation at intermediate values;
  //   • track.enabled = false at exactly zero, because a platform that quietly
  //     ignores setVolume would otherwise leave 0% audible, and "خالص" has to
  //     mean silent on every device.
  // ============================================================

  double _remoteVolume = 1.0;

  double get remoteVolume => _remoteVolume;

  /// [volume] is 0..1. Zero is a hard mute, not merely a quiet setting.
  Future<void> setRemoteVolume(double volume) async {
    _remoteVolume = volume.clamp(0.0, 1.0);
    for (final stream in _remoteStreams.values) {
      await _applyVolumeToStream(stream);
    }
    _log('setRemoteVolume(${_remoteVolume.toStringAsFixed(2)}) '
        'across ${_remoteStreams.length} peer(s)');
  }

  Future<void> _applyVolumeToStream(MediaStream stream) async {
    for (final track in stream.getAudioTracks()) {
      track.enabled = _remoteVolume > 0;
      if (_remoteVolume > 0) {
        try {
          await Helper.setVolume(_remoteVolume, track);
        } catch (e) {
          // Not every platform implements per-track gain; `enabled` above still
          // guarantees the mute case, which is the reported behaviour.
          _log('setVolume unsupported on this platform: $e');
        }
      }
    }
  }

  /// Set speaker on/off.
  ///
  /// A3 — records the choice in [AudioRoute] and pushes it to the registered
  /// game players as well, so "كل صوت يخرج منها" holds for the room AND the
  /// games rather than just the voice stream.
  Future<void> setSpeakerphoneOn(bool on) async {
    _isSpeakerOn = on;
    AudioRoute.instance.speakerOn = on;
    unawaited(AudioRoute.instance.apply());

    // Android route
    if (!kIsWeb && Platform.isAndroid) {
      await _applyAndroidAudioRoute(speakerOn: on);
    }

    // iOS route (also works with Helper)
    if (!kIsWeb && Platform.isIOS) {
      try {
        await Helper.setSpeakerphoneOn(on);
      } catch (e) {
        _log('⚠️ iOS setSpeakerphoneOn failed: $e');
      }
    }

    _log(on ? '🔊 Speaker ON' : '🔇 Speaker OFF');
  }


  /// Get microphone status
  bool get isMicMuted => _isMicMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  MediaStream? get localStream => _localStream;
  Map<int, MediaStream> get remoteStreams => _remoteStreams;
  int get peerConnectionCount => _peerConnections.length;

  /// Make sure [pc] is actually sending OUR microphone.
  ///
  /// Reusing a live peer is right — rebuilding a working transport costs a
  /// gap in the audio — but only once it carries the current local track.
  /// Silent no-op while listen-only: there is deliberately no microphone then.
  Future<void> _ensureSenderOn(RTCPeerConnection pc, int otherUserId) async {
    if (_listenOnly) return;
    final track = _localAudioTrack;
    if (track == null) return;

    try {
      final senders = await pc.getSenders();
      RTCRtpSender? audioSender;
      for (final s in senders) {
        if (s.track?.kind == 'audio') {
          audioSender = s;
          break;
        }
      }

      if (audioSender == null) {
        // No sender at all — this peer was built listen-only. Adding a track
        // changes the shape of the session, so it needs renegotiating.
        await pc.addTrack(track, _localStream!);
        _log('🎙️ Attached mic to reused peer $otherUserId — renegotiating');
        await _sendOffer(otherUserId);
        return;
      }

      if (identical(audioSender.track, track)) return;

      // A sender exists but points at a track we have since replaced. swapping
      // it in place needs no renegotiation, so the room hears no gap.
      await audioSender.replaceTrack(track);
      _log('🔁 Swapped stale mic track on reused peer $otherUserId');
    } catch (e) {
      _log('⚠️ could not ensure sender for $otherUserId: $e');
    }
  }

  /// Is this connection still worth using?
  bool _isPeerUsable(RTCPeerConnection pc) {
    if (pc.signalingState == RTCSignalingState.RTCSignalingStateClosed) {
      return false;
    }
    final conn = pc.connectionState;
    if (conn == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
        conn == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
      return false;
    }
    final ice = pc.iceConnectionState;
    if (ice == RTCIceConnectionState.RTCIceConnectionStateFailed ||
        ice == RTCIceConnectionState.RTCIceConnectionStateClosed) {
      return false;
    }
    return true;
  }

  /// Bring a broken peer back.
  ///
  /// The first two attempts ask ICE to find a new path. That keeps the
  /// transceivers, the tracks and the whole audio pipeline in place and
  /// recovers in well under a second. Only a failure that survives both earns a
  /// full rebuild — the old code went straight to the teardown, and because
  /// BOTH ends did it at the same moment the replacement offer regularly landed
  /// on a peer still disposing of the connection it was meant to replace.
  ///
  /// Only the initiator drives recovery, for the same reason: two ends racing
  /// to repair one link is what left it broken.
  Future<void> _recoverPeer(int otherUserId) async {
    if (_restarting.contains(otherUserId)) return;
    if (_currentRoomId == null || _currentUserId == null) return;

    _iceFailTimers.remove(otherUserId)?.cancel();

    final pc = _peerConnections[otherUserId];
    if (pc == null) return;

    final attempt = (_recoveryAttempts[otherUserId] ?? 0) + 1;
    _recoveryAttempts[otherUserId] = attempt;
    final drives = _shouldInitiateWith(otherUserId);

    _restarting.add(otherUserId);
    try {
      if (attempt <= 2) {
        if (!drives) {
          _log('🩹 Waiting for $otherUserId to drive recovery #$attempt');
          return;
        }
        _log('🩹 ICE restart #$attempt with $otherUserId');
        try {
          await pc.restartIce();
        } catch (e) {
          _log('⚠️ restartIce unavailable ($e) — re-offering instead');
        }
        // The fresh offer must be applied by the far end, so the candidates it
        // trickles back belong to the new generation.
        _remoteDescriptionSet.remove(otherUserId);
        _pendingCandidates.remove(otherUserId);
        await _sendOffer(otherUserId, iceRestart: true);
        return;
      }

      _log('🔁 Rebuilding peer connection with $otherUserId (attempt $attempt)');
      await _disposePeer(otherUserId);
      await _createPeerConnection(otherUserId, isInitiator: drives);
    } catch (e) {
      _log('❌ recoverPeer error: $e');
    } finally {
      _restarting.remove(otherUserId);
    }
  }

  /// Close one peer and forget every piece of state that belongs to it.
  /// Leaving any of it behind is what made a rebuilt connection inherit the
  /// previous one's candidates and negotiation flags.
  Future<void> _disposePeer(int otherUserId, {bool notify = false}) async {
    _iceFailTimers.remove(otherUserId)?.cancel();
    _makingOffer.remove(otherUserId);
    _remoteDescriptionSet.remove(otherUserId);
    _pendingCandidates.remove(otherUserId);

    final pc = _peerConnections.remove(otherUserId);
    if (pc != null) {
      try {
        await pc.close();
      } catch (e) {
        _log('⚠️ closing peer $otherUserId: $e');
      }
    }

    final renderer = _remoteRenderers.remove(otherUserId);
    if (renderer != null) {
      try {
        await renderer.dispose();
      } catch (_) {}
      _audioRenderers.remove(renderer);
    }
    _remoteStreams.remove(otherUserId);

    if (notify) onRemoteStreamRemoved?.call(otherUserId);
  }

  /// Drop the entire mesh, keeping the local microphone. Used when the socket
  /// comes back: every connection negotiated over the old one is unrecoverable,
  /// because the signalling path that could have repaired it is gone.
  Future<void> _teardownAllPeers() async {
    for (final otherUserId in _peerConnections.keys.toList()) {
      await _disposePeer(otherUserId, notify: true);
    }
    _recoveryAttempts.clear();
    _restarting.clear();
  }

  /// Apply the candidates held for a peer now that its remote description is
  /// in place, and let later ones through directly.
  Future<void> _flushPendingCandidates(int otherUserId) async {
    _remoteDescriptionSet.add(otherUserId);

    final pc = _peerConnections[otherUserId];
    final queued = _pendingCandidates.remove(otherUserId);
    if (pc == null || queued == null || queued.isEmpty) return;

    for (final candidate in queued) {
      try {
        await pc.addCandidate(candidate);
      } catch (e) {
        _log('⚠️ buffered candidate from $otherUserId rejected: $e');
      }
    }
    _log('❄️ Applied ${queued.length} buffered candidate(s) from $otherUserId');
  }


  /// Close peer connection with specific user
  void _closePeerConnection(int otherUserId) {
    _recoveryAttempts.remove(otherUserId);
    unawaited(
      _disposePeer(otherUserId, notify: true).then(
        (_) => debugPrint('✅ Closed peer connection with user $otherUserId'),
      ),
    );
  }

  /// Dispose all resources
  Future<void> dispose() async {
    try {
      debugPrint('🧹 Disposing WebRTC service...');

      _initialized = false;

      await _reconnectSub?.cancel();
      _reconnectSub = null;

      for (final t in _iceFailTimers.values) {
        t.cancel();
      }
      _iceFailTimers.clear();
      _pendingCandidates.clear();
      _remoteDescriptionSet.clear();
      _makingOffer.clear();
      _restarting.clear();
      _recoveryAttempts.clear();
      _listenOnly = false;

      _statsTimer?.cancel();
      _statsTimer = null;

      // Stop VAD timer
      _vadEnabled = false;
      _vadTimer?.cancel();
      _vadTimer = null;
      _vadSpeaking = false;
      _vadQuietTicks = 0;
      _audioLevel = 0.0;

      // Close all peer connections
      for (var entry in _peerConnections.entries) {
        try {
          entry.value.close();
        } catch (e) {
          debugPrint('⚠️ Error closing peer connection: $e');
        }
      }
      _peerConnections.clear();

      // Dispose all renderers
      for (var renderer in _audioRenderers) {
        try {
          await renderer.dispose();
        } catch (e) {
          debugPrint('⚠️ Error disposing renderer: $e');
        }
      }
      _audioRenderers.clear();
      _remoteRenderers.clear();

      // Stop local stream
      if (_localStream != null) {
        for (var track in _localStream!.getTracks()) {
          _detachTrackWatch(track);
          await track.stop();
        }
        _localStream = null;
        _localAudioTrack = null;
      }

      _socketService.emit('user_left_voice', {
        'roomId': _currentRoomId,
        'userId': _currentUserId,
      });

      debugPrint('✅ WebRTC service disposed');
    } catch (e) {
      debugPrint('❌ Error disposing WebRTC: $e');
    }
  }

  /// Enable Voice Activity Detection (VAD). Safe to call repeatedly.
  void enableVAD() {
    if (_vadEnabled) return;
    _vadEnabled = true;
    _audioLevel = 0.0;
    _vadQuietTicks = 0;
    _vadSpeaking = false;
    _startVoiceActivityDetection();
    debugPrint('✅ VAD enabled');
  }

  /// Disable Voice Activity Detection.
  ///
  /// Takes the ring down on the way out: leaving a seat while the last reading
  /// was "speaking" would otherwise leave the pulse lit on an empty mic.
  void disableVAD() {
    _vadEnabled = false;
    _vadTimer?.cancel();
    _vadTimer = null;
    _vadQuietTicks = 0;
    _emitSpeaking(false);
    debugPrint('❌ VAD disabled');
  }

  /// Start monitoring voice activity.
  ///
  /// Deliberately does NOT touch the mic. The previous implementation auto-muted
  /// after half a second of "silence" and auto-unmuted on "speech" — driven by a
  /// level that was never measured, so in practice it only ever muted people.
  /// VAD's job here is to report, not to moderate.
  void _startVoiceActivityDetection() {
    _vadTimer?.cancel();
    _vadTimer = Timer.periodic(_vadInterval, (timer) async {
      if (!_vadEnabled) {
        timer.cancel();
        return;
      }
      if (_localStream == null) {
        // Not on a mic (yet): make sure a ring left over from the last seat
        // does not stay lit.
        _emitSpeaking(false);
        return;
      }

      try {
        final level = await _readLocalAudioLevel();
        if (level != null) _audioLevel = level;

        // A muted mic is never "speaking", whatever the source reports — the
        // track keeps producing samples while `enabled` is false on some
        // platforms. The track's own flag is the truth here: `_isMicMuted` only
        // tracks the mute/unmute pair, and `_localMuted` is written by
        // setLocalMuted, which this app never calls.
        final trackLive = _localAudioTrack?.enabled ?? !_isMicMuted;
        final loud = trackLive && !_isMicMuted && _audioLevel >= _vadSpeakingLevel;

        if (loud) {
          _vadQuietTicks = 0;
          _emitSpeaking(true);
        } else {
          _vadQuietTicks++;
          if (_vadQuietTicks >= _vadQuietTicksToStop) _emitSpeaking(false);
        }
      } catch (e) {
        debugPrint('⚠️ VAD error: $e');
      }
    });
  }

  /// Fire [onVoiceActivityChanged] on TRANSITIONS only — the callback ends up
  /// emitting a socket event, so calling it five times a second while somebody
  /// talks would be a flood.
  void _emitSpeaking(bool speaking) {
    if (_vadSpeaking == speaking) return;
    _vadSpeaking = speaking;
    onVoiceActivityChanged?.call(speaking);
  }

  /// Current microphone level, 0..1, or null when it cannot be read.
  ///
  /// `media-source` carries the level of the LOCAL capture and is identical on
  /// every peer connection, so one connection is enough. With nobody else on a
  /// mic there is no connection and therefore no reading — an empty room has no
  /// audience for the ring either.
  Future<double?> _readLocalAudioLevel() async {
    if (_peerConnections.isEmpty) return null;
    final pc = _peerConnections.values.first;
    try {
      final stats = await pc.getStats();
      double? fallback;
      for (final r in stats) {
        final kind = r.values['kind'] ?? r.values['mediaType'];
        if (kind != 'audio') continue;
        final raw = r.values['audioLevel'];
        final level = raw is num ? raw.toDouble() : double.tryParse('$raw');
        if (level == null || level.isNaN) continue;

        // `media-source` is the local capture and the reading we want.
        if (r.type == 'media-source') return level.clamp(0.0, 1.0).toDouble();

        // Not every platform reports media-source. `outbound-rtp` describes
        // what WE are sending, so it is the same voice; inbound is the OTHER
        // side's and would light our ring while somebody else talks.
        if (r.type == 'outbound-rtp' || r.type == 'sender') {
          fallback ??= level.clamp(0.0, 1.0).toDouble();
        }
      }
      return fallback;
    } catch (_) {
      // A connection closing mid-poll throws; the next tick will pick up
      // another one.
    }
    return null;
  }

  /// Feed an externally measured level (0..1). Kept for callers that have a
  /// better source than WebRTC stats; the poll above is the default.
  void updateAudioLevel(double level) {
    _audioLevel = level.clamp(0.0, 1.0).toDouble();
  }

  /// Enable Push-to-Talk mode
  void enablePTT() {
    _pttMode = true;
    _isPttActive = false;
    // Auto-mute when enabling PTT
    muteAudio();
    debugPrint('✅ PTT mode enabled');
  }

  /// Disable Push-to-Talk mode
  void disablePTT() {
    _pttMode = false;
    _isPttActive = false;
    debugPrint('❌ PTT mode disabled');
  }

  /// Start talking (PTT press)
  Future<void> startPTT() async {
    if (!_pttMode) return;
    _isPttActive = true;
    await unmuteAudio();
    debugPrint('🎯 PTT activated - speaking');
  }

  /// Stop talking (PTT release)
  Future<void> stopPTT() async {
    if (!_pttMode) return;
    _isPttActive = false;
    await muteAudio();
    debugPrint('🎯 PTT deactivated - muted');
  }

  /// Check if PTT mode is enabled
  bool get isPTTMode => _pttMode;
  bool get isPTTActive => _isPttActive;
}
