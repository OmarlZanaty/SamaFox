import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:samafox/utils/permission_gate.dart';

import '../config/app_config.dart';
import 'socket_service.dart';
import 'audio_route.dart';
import 'crash_reporter.dart';
import 'voice_engine.dart';


/// Complete WebRTC Audio Service with Peer Connections
/// Handles voice chat between multiple users in a room
///
/// This is the **mesh** engine: every phone connects directly to every other
/// phone. See [VoiceEngine] for the interface and [LiveKitVoiceEngine] for the
/// SFU alternative the server can switch rooms to.
class WebRTCAudioService implements VoiceEngine {
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

  /// One build in flight per peer. `_createPeerConnection` is reached from
  /// four places within milliseconds of a (re)connect — the voice-user list,
  /// `user_joined_voice`, an incoming offer and the socket-reconnect sweep —
  /// and every one of them checked `_peerConnections[id]`, found nothing
  /// (the first build was still inside `await createPeerConnection`), and
  /// built its own. The device log showed it plainly: five `peer +26 (live=1)`
  /// crumbs inside 60 ms. Four native connections were then overwritten in
  /// the map and never closed, and RSS went from 300 MB to 1.3 GB within a
  /// minute of entering the room, until Android killed the process.
  final Map<int, Future<RTCPeerConnection>> _peerBuilds = {};
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

  /// Who holds a mic right now, per the server's last snapshot. Null until a
  /// snapshot that carries it arrives (an older server never sends one).
  ///
  /// This is what shrinks the mesh. A listener needs a connection to every
  /// speaker and to nobody else; two listeners have nothing to exchange. So a
  /// pair gets a connection only when at least one of them is a speaker. In a
  /// room of 20 with 8 on the mics a listener holds 8 connections instead of
  /// 19, which is the difference between a phone that keeps up and one that
  /// drops audio — or dies.
  ///
  /// Speakers still connect to everyone: that is the mesh's ceiling and only an
  /// SFU moves it. The snapshot is the single source of truth for both sides of
  /// a pair, so they always agree on whether a link should exist.
  Set<int>? _speakers;

  bool _pairNeedsLink(int otherUserId) {
    final speakers = _speakers;
    if (speakers == null) return true; // old server: full mesh, as before
    final me = _currentUserId;
    return (me != null && speakers.contains(me)) ||
        speakers.contains(otherUserId);
  }

  /// Peers we have stopped chasing, and the timers pacing the attempts.
  ///
  /// The recovery ladder used to have NO ceiling: attempts 1-2 restarted ICE and
  /// every attempt from 3 on rebuilt the peer connection, immediately, on the
  /// next failure — forever. For a peer with no possible network path (both
  /// sides behind carrier-grade NAT and no TURN server) that is an infinite
  /// loop: fail, rebuild, gather, fail, rebuild, roughly every 10-20 seconds,
  /// for every unreachable member of the room at once. It burned radio and CPU,
  /// and each turn of it leaked a native peer connection, which is what killed
  /// the app about a minute after entering a room.
  ///
  /// So: a hard ceiling, growing delays between attempts, and then we stop and
  /// say so. A stopped peer is retried when something actually changes — the
  /// socket reconnects, or that user re-announces themselves in voice.
  final Set<int> _unreachablePeers = {};
  final Map<int, Timer> _recoveryTimers = {};

  /// 2 ICE restarts, then at most 3 rebuilds.
  static const int _maxRecoveryAttempts = 5;

  /// Delay before each rebuild attempt (attempt 3, 4, 5).
  static const List<Duration> _rebuildBackoff = [
    Duration(seconds: 4),
    Duration(seconds: 10),
    Duration(seconds: 20),
  ];

  /// Called once per session when a peer is given up on, so the room can tell
  /// the user their network is blocking direct voice instead of leaving them
  /// wondering why one person is silent.
  Function(int userId)? onPeerUnreachable;

  /// True while the session was opened without a microphone.
  bool _listenOnly = false;

  /// Guards [_recoverLocalMic] against re-entry.
  bool _recoveringMic = false;

  /// Retry timer for a recovery that could not get the microphone back yet.
  ///
  /// A phone call is the case this exists for. The call takes the microphone,
  /// our track ends, `onEnded` fires ONCE, the re-capture fails because
  /// telephony still owns the device — and before this there was nothing left
  /// to try again, so the user came back from the call live on a seat and
  /// inaudible until they left the room and re-entered. Now the attempt is
  /// repeated with a backoff until the platform hands the microphone back.
  Timer? _micRetryTimer;
  int _micRetryAttempt = 0;

  /// Watches a mic that is supposed to be live and is not.
  ///
  /// `onEnded` is not always delivered: an interruption can leave a track that
  /// still reports `enabled = true` while the platform has muted it or the
  /// capture has stopped producing samples. Both are silence at the far end
  /// and neither raises an event, so they are polled for.
  Timer? _micWatchdog;
  double? _lastSamplesDuration;
  int _micStallTicks = 0;

  /// Stall-triggered recoveries that did not make the counter move again.
  ///
  /// The frozen-samples check is a heuristic, and a heuristic that re-opens the
  /// microphone in a loop would be worse than the silence it is looking for. If
  /// three re-captures in a row do not get the counter moving, this device is
  /// not reporting it and the signal is dropped — the platform-mute and
  /// track-ended checks, which are facts rather than inference, stay on.
  int _stallRecoveries = 0;
  static const int _maxStallRecoveries = 3;

  /// How many consecutive watchdog ticks of frozen samples count as a dead
  /// capture. At 3s a tick this is ~9s of an unmuted mic sending nothing.
  static const int _micStallTicksToRecover = 3;
  static const Duration _micWatchdogInterval = Duration(seconds: 3);

  /// Is the app the one the user is looking at?
  ///
  /// It decides how hard we are allowed to chase the microphone. In the
  /// foreground, immediately — the user is in the room and expects to be heard.
  /// In the background, at most once every [_backgroundRecoveryCooldown]:
  /// *"ريكورد الواتس او اي شئ يشتغل عادي علي الوضع الموجود"*. Android gives the
  /// foreground app the microphone, so our attempts fail harmlessly while
  /// someone records a voice note elsewhere — but attempting every three
  /// seconds would be picking a fight with their recorder for no benefit.
  bool _appForeground = true;
  DateTime? _lastMicRecoveryAt;
  static const Duration _backgroundRecoveryCooldown = Duration(seconds: 12);

  /// Never two recoveries closer than this, whatever asked for them.
  static const Duration _micRecoveryCooldown = Duration(seconds: 8);

  /// And never more than this many in the window. Past it the watchdog is
  /// stopped for the rest of the seat: a microphone that has been re-opened
  /// eight times in five minutes is not going to be fixed by a ninth.
  static const int _maxMicRecoveriesPerWindow = 8;
  static const Duration _micRecoveryWindow = Duration(minutes: 5);
  final List<DateTime> _micRecoveryTimes = [];
  bool _micRecoveryExhausted = false;

  /// Watches the app's own lifecycle, so this does not depend on a screen being
  /// mounted: the session outlives the room screen (the PiP bubble keeps it
  /// running), and a microphone interrupted while collapsed into the bubble has
  /// to be repaired just the same.
  _AudioLifecycleWatcher? _lifecycleWatcher;

  void _watchAppLifecycle() {
    if (_lifecycleWatcher != null) return;
    final watcher = _AudioLifecycleWatcher(setAppForeground);
    WidgetsBinding.instance.addObserver(watcher);
    _lifecycleWatcher = watcher;
  }

  void _unwatchAppLifecycle() {
    final watcher = _lifecycleWatcher;
    if (watcher == null) return;
    WidgetsBinding.instance.removeObserver(watcher);
    _lifecycleWatcher = null;
    _appForeground = true;
  }

  void setAppForeground(bool foreground) {
    if (_appForeground == foreground) return;
    _appForeground = foreground;
    if (foreground) {
      // Back in front: the next attempt is allowed to be immediate again. A
      // retry already scheduled on the slow background cadence would otherwise
      // keep the user waiting up to twelve seconds for a mic they are looking
      // at, so it is replaced with an attempt right now.
      _micRetryAttempt = 0;
      _lastMicRecoveryAt = null;
      final pending = _micRetryTimer != null;
      _micRetryTimer?.cancel();
      _micRetryTimer = null;
      if (pending && _initialized && !_listenOnly) {
        unawaited(_recoverLocalMic());
      }
    }
    _log('app ${foreground ? 'foreground' : 'background'}');
  }

  /// May a recovery run right now? See [_appForeground].
  bool get _recoveryAllowedNow {
    if (_appForeground) return true;
    final last = _lastMicRecoveryAt;
    return last == null ||
        DateTime.now().difference(last) >= _backgroundRecoveryCooldown;
  }

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

    // The server's TURN wins over the one compiled into this build, so the
    // relay can move without an app release (see VoiceEngineConfig.turnUrls).
    final fromServer = VoiceEngineConfig.turnUrls.isNotEmpty;
    final rawUrls = fromServer ? VoiceEngineConfig.turnUrls : AppConfig.turnUrls;
    final username =
        fromServer ? VoiceEngineConfig.turnUsername : AppConfig.turnUsername;
    final credential =
        fromServer ? VoiceEngineConfig.turnCredential : AppConfig.turnCredential;
    final turnUrls = rawUrls
        .split(',')
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
    if (turnUrls.isNotEmpty) {
      servers.add(<String, dynamic>{
        'urls': turnUrls,
        if (username.isNotEmpty) 'username': username,
        if (credential.isNotEmpty) 'credential': credential,
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
    // BISECT 2026-09-13: back to the exact constants this used before the
    // تقليل الضوضاء toggle was wired in. On a freshly booted phone the capture
    // was returning totalSamples=0.0 — a live, enabled track delivering
    // silence — and these constraints are the only thing that changed in this
    // method. If the microphone works with these, the toggle has to drive
    // suppression some other way (applyConstraints on the track, or a
    // processing flag) rather than by varying what getUserMedia is asked for.
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,

        // WebRTC Android legacy keys (plugin prints these)
        'googEchoCancellation': true,
        'googEchoCancellation2': true,
        'googDAEchoCancellation': true,
        'googNoiseSuppression': true,
        'googAutoGainControl': true,
        'googHighpassFilter': true,

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

  /// Re-acquire the microphone, and keep trying until it comes back.
  ///
  /// Returns true once a live track is publishing again.
  Future<bool> _recoverLocalMic() async {
    if (_recoveringMic || _listenOnly || !_initialized) return false;

    // Hard limits, independent of WHO asked for the recovery. The trigger that
    // looped was a misread `muted` flag, but any trigger that fires repeatedly
    // (a track that ends the instant it is opened, a device that keeps
    // reporting a fault) must land here and be stopped, not just the one that
    // was found: every re-capture opens a new native audio source, and the
    // observed 2,458 of them took the process to 1.2 GB and its death.
    final now = DateTime.now();
    final last = _lastMicRecoveryAt;
    if (last != null && now.difference(last) < _micRecoveryCooldown) {
      _log('mic recovery skipped: within cooldown');
      _scheduleMicRetry();
      return false;
    }
    _micRecoveryTimes.removeWhere((t) => now.difference(t) > _micRecoveryWindow);
    if (_micRecoveryTimes.length >= _maxMicRecoveriesPerWindow) {
      if (!_micRecoveryExhausted) {
        _micRecoveryExhausted = true;
        _log('⛔ mic recovery exhausted: $_maxMicRecoveriesPerWindow in '
            '${_micRecoveryWindow.inMinutes}m — stopping until the seat changes');
        CrashReporter.event('mic', 'recovery exhausted — stopped', level: 'warn');
        _stopMicWatchdog();
      }
      return false;
    }
    _micRecoveryTimes.add(now);

    _recoveringMic = true;
    _lastMicRecoveryAt = now;
    var recovered = false;
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
        // The stream object is native too. Stopping the tracks releases the
        // microphone; without this the stream itself stayed allocated — one
        // per recovery.
        try {
          await old.dispose();
        } catch (_) {}
      }

      await _captureLocalStream();
      final track = _localAudioTrack;
      if (track == null) {
        _log('❌ mic recovery: no track after re-capture');
        _scheduleMicRetry();
        return false;
      }
      track.enabled = !wasMuted;

      // Swap the new track into every live sender. `replaceTrack` does this in
      // place, so the peers keep their transceivers and no renegotiation
      // round-trip (and no audible gap) is needed.
      // Snapshot: every await here yields, and a peer can be disposed by an ICE
      // event in the gap — "Concurrent modification during iteration" was the
      // uncaught error the phones reported.
      for (final entry in _peerConnections.entries.toList()) {
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
      // The call (or whatever took the microphone) also took the audio route
      // with it: Android comes back in whatever mode telephony left behind.
      // Put the user's own choice back so the room sounds the way it did
      // before the interruption — "مع اغلاق المكالمه المفروض الوضع يرجع كما كان".
      await _applyEchoSafeMode(talking: !wasMuted);

      _micRetryTimer?.cancel();
      _micRetryTimer = null;
      _micRetryAttempt = 0;
      _lastSamplesDuration = null;
      _micStallTicks = 0;
      recovered = true;
      _log('✅ microphone re-acquired');
      CrashReporter.breadcrumb('mic re-acquired');
    } catch (e) {
      _log('❌ mic recovery failed: $e');
      _scheduleMicRetry();
    } finally {
      _recoveringMic = false;
    }
    return recovered;
  }

  /// Try again shortly. Backs off 1s, 2s, 4s then every 5s for as long as the
  /// user is supposed to be on a live microphone.
  ///
  /// It never gives up on its own: the interruption can last as long as the
  /// phone call does, and stopping after N attempts would just move the silent
  /// mic further down the call. It IS bounded by state — leaving the seat, the
  /// room or the app tears the timer down with everything else — and a failing
  /// attempt costs one `getUserMedia` call, which the platform refuses
  /// immediately while another app is recording. That is what keeps a WhatsApp
  /// voice note (or any other recorder) working: we ask, Android says no, and
  /// nothing is taken away from the app in the foreground.
  void _scheduleMicRetry() {
    if (_listenOnly || !_initialized) return;
    if (_micRetryTimer != null) return;

    const delays = <Duration>[
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ];
    final delay = !_appForeground
        ? _backgroundRecoveryCooldown
        : (_micRetryAttempt < delays.length
            ? delays[_micRetryAttempt]
            : const Duration(seconds: 5));
    _micRetryAttempt++;

    _log('⏳ mic retry #$_micRetryAttempt in ${delay.inMilliseconds}ms');
    _micRetryTimer = Timer(delay, () async {
      _micRetryTimer = null;
      if (_listenOnly || !_initialized) return;
      if (micHealthy) {
        _micRetryAttempt = 0;
        return;
      }
      await _recoverLocalMic();
    });
  }

  /// Re-assert the user's chosen output route (loudspeaker or earpiece).
  ///
  /// A phone call leaves Android in whatever audio mode telephony was using, so
  /// everyone in the room — listeners included, who have no microphone to
  /// repair — needs the route put back when it ends. Idempotent and cheap.
  Future<void> reapplyAudioRoute() async {
    await _applyEchoSafeMode(talking: !_isMicMuted);
  }

  /// Public entry point for "make sure I can still be heard".
  ///
  /// Called when the app comes back to the foreground and after an
  /// interruption, where the cheapest correct thing is to check rather than to
  /// assume. A healthy microphone makes this a no-op.
  Future<void> ensureMicAlive() async {
    if (!_initialized || _listenOnly) return;
    if (micHealthy) {
      // Alive — but the route may still be whatever the interruption left.
      await _applyEchoSafeMode(talking: !_isMicMuted);
      return;
    }
    await _recoverLocalMic();
  }

  /// Poll a microphone that is supposed to be live.
  ///
  /// Two failures are invisible to `onEnded`: a track the platform has muted
  /// (an incoming call does exactly this), and a track that is still "live"
  /// while its capture has stopped producing samples. Both sound identical to
  /// everyone else in the room — nothing at all — so both are recovered from
  /// here.
  void _startMicWatchdog() {
    _micWatchdog?.cancel();
    _lastSamplesDuration = null;
    _micStallTicks = 0;
    _micRecoveryTimes.clear();
    _micRecoveryExhausted = false;
    _micWatchdog = Timer.periodic(_micWatchdogInterval, (_) async {
      if (!_initialized || _listenOnly) return;
      // Muted = the capture is deliberately released. Nothing to watch.
      if (_isMicMuted) return;
      if (_recoveringMic || _micRetryTimer != null) return;
      if (!_recoveryAllowedNow) return;

      final track = _localAudioTrack;
      if (_localStream == null || track == null) {
        _log('👁️ watchdog: no local track while on a mic — recovering');
        await _recoverLocalMic();
        return;
      }

      // NOTE: `track.muted` is deliberately NOT consulted. In flutter_webrtc it
      // is `!enabled` — it means the USER muted the mic, not that the platform
      // took it. Reading it as an interruption made this watchdog re-capture
      // the microphone every three seconds for every self-muted speaker,
      // 2,458 times in one observed session, until the phone ran out of memory
      // and Android killed the app. The ended-track event and the frozen-
      // samples check are the only signals with an actual fault behind them.

      // Only a mic that is meant to be transmitting can be judged by its
      // samples: a muted one is silent on purpose.
      if (_isMicMuted || _peerConnections.isEmpty) {
        _lastSamplesDuration = null;
        _micStallTicks = 0;
        return;
      }

      final samples = await _readLocalSamplesDuration();
      if (samples == null) {
        _micStallTicks = 0;
        return;
      }
      final last = _lastSamplesDuration;
      _lastSamplesDuration = samples;
      if (last == null) return;

      if (samples > last) {
        _micStallTicks = 0;
        // The counter is moving again, so whatever we did worked — and the next
        // freeze is a fresh fault, not a repeat of this one.
        _stallRecoveries = 0;
        return;
      }

      _micStallTicks++;
      if (_micStallTicks >= _micStallTicksToRecover) {
        _micStallTicks = 0;
        _lastSamplesDuration = null;
        if (_stallRecoveries >= _maxStallRecoveries) {
          _log('👁️ watchdog: samples still frozen after '
              '$_stallRecoveries recoveries — ignoring this signal');
          return;
        }
        _stallRecoveries++;
        _log('👁️ watchdog: capture frozen at $samples — recovering '
            '(#$_stallRecoveries)');
        await _recoverLocalMic();
      }
    });
  }

  void _stopMicWatchdog() {
    _micWatchdog?.cancel();
    _micWatchdog = null;
    _micRetryTimer?.cancel();
    _micRetryTimer = null;
    _micRetryAttempt = 0;
    _lastSamplesDuration = null;
    _micStallTicks = 0;
    _stallRecoveries = 0;
  }

  /// `totalSamplesDuration` of the LOCAL capture, which only moves while the
  /// microphone is actually producing audio. Null when it cannot be read.
  Future<double?> _readLocalSamplesDuration() async {
    if (_peerConnections.isEmpty) return null;
    final pc = _peerConnections.values.first;
    try {
      final stats = await pc.getStats();
      for (final r in stats) {
        if (r.type != 'media-source') continue;
        final kind = r.values['kind'] ?? r.values['mediaType'];
        if (kind != 'audio') continue;
        final raw = r.values['totalSamplesDuration'];
        final v = raw is num ? raw.toDouble() : double.tryParse('$raw');
        if (v != null && !v.isNaN) return v;
      }
    } catch (_) {
      // A connection closing mid-poll throws; the next tick picks another one.
    }
    return null;
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
      final res = await PermissionGate.request(Permission.microphone);
      _log('Mic permission request result: $res');
    }

    if (!kIsWeb && Platform.isAndroid) {
      await _forceAndroidVoiceRoute();
    }

  }

  /// The sender that carries (or carried) OUR microphone on [pc].
  ///
  /// After [_releaseLocalMic] the sender is still there but its track is null,
  /// so `track?.kind == 'audio'` no longer finds it. Looking only at the track
  /// meant every mute/unmute added a brand-new transceiver to every peer — a
  /// new m-line, a renegotiation and a leaked sender per cycle. The transceiver
  /// still knows what its m-line is for; a sending one with no track is ours.
  Future<RTCRtpSender?> _findAudioSender(RTCPeerConnection pc) async {
    final senders = await pc.getSenders();
    for (final s in senders) {
      if (s.track?.kind == 'audio') return s;
    }
    try {
      for (final t in await pc.getTransceivers()) {
        if (t.sender.track != null) continue;
        if (t.receiver.track?.kind != 'audio') continue;
        final dir = await t.getDirection();
        if (dir == TransceiverDirection.SendRecv ||
            dir == TransceiverDirection.SendOnly) {
          return t.sender;
        }
      }
    } catch (e) {
      _log('⚠️ transceiver lookup failed: $e');
    }
    return null;
  }

  Future<void> _attachLocalTrackToAllPeers() async {
    if (_localStream == null) return;

    final track = _localAudioTrack ??
        (_localStream!.getAudioTracks().isNotEmpty
            ? _localStream!.getAudioTracks().first
            : null);
    if (track == null) return;

    for (final entry in _peerConnections.entries.toList()) {
      final pc = entry.value;
      try {
        final sender = await _findAudioSender(pc);
        if (sender == null) {
          await pc.addTrack(track, _localStream!);
          _log('🎙️ Added mic track to peer ${entry.key}');
        } else if (sender.track?.id != track.id) {
          // Our own sender, emptied by mute: put the new track back in place.
          // No renegotiation needed, so the room hears no gap.
          await sender.replaceTrack(track);
          _log('🔁 Restored mic track on peer ${entry.key}');
        }
      } catch (e) {
        _log('⚠️ attaching mic to peer ${entry.key} failed: $e');
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
    // From here on the microphone is supposed to be producing audio, so it is
    // worth watching: this is the only state in which silence is a fault.
    _startMicWatchdog();

    // As a listener this client skipped every other listener. Now that it
    // speaks, those links are needed. The seat change already makes the server
    // broadcast a new snapshot; asking for one directly covers the case where
    // that broadcast raced ahead of the capture above.
    if (_currentRoomId != null) {
      _socketService.emit('get_voice_users', {'roomId': _currentRoomId});
    }
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

    // Entering a DIFFERENT room ends the session in the old one first.
    //
    // This service is a singleton keyed by `_currentRoomId`, and nothing used
    // to reset it: opening room B while room A was still live kept every peer
    // connection from A, never sent `user_left_voice` to A, and left the
    // microphone published there. The client's report is exactly that —
    // "لما ادخل اي غرفه بفضل معلق علي المايك في الغرفه اللي قبلها" — and his voice
    // kept going to the room he thought he had left.
    if (_initialized && _currentRoomId != null && _currentRoomId != roomId) {
      _log('🚪 switching rooms: leaving $_currentRoomId before joining $roomId');
      await leaveVoice();
    }

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
    _watchAppLifecycle();
    CrashReporter.breadcrumb(
      'voice init room=$roomId listenOnly=$listenOnly',
    );

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
      _startMicWatchdog();
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
      _stopMicWatchdog();
      _statsTimer?.cancel();
      _statsTimer = null;
      final local = _localStream;
      _localStream = null;
      _localAudioTrack = null;
      if (local != null) {
        for (final t in local.getTracks()) {
          _detachTrackWatch(t);
          try { await t.stop(); } catch (_) {}
        }
        // The stream object is native as well; dropping the reference alone
        // leaves it allocated for the life of the process.
        try { await local.dispose(); } catch (_) {}
      }

      // close all peer connections and everything hanging off them
      await _teardownAllPeers();
      _audioRenderers.clear();

      _initialized = false;
      _listenOnly = false;
      _speakers = null;
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

  /// Ticks of the 2-second stats poll between telemetry events (~16s).
  int _statsTick = 0;
  static const int _statsReportEvery = 8;

  void startMicStats() {
    _statsTimer?.cancel();

    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_peerConnections.isEmpty) return;

      // The log lines below stay on the phone. What the SERVER needs is a
      // compact picture every ~16s: per peer, is the link up and are audio
      // bytes actually moving in each direction. "I can't hear anyone" is
      // undiagnosable without it — a connected peer with rx=0 and a peer that
      // never connected are different bugs with the same symptom.
      final report = (++_statsTick % _statsReportEvery == 0);
      final peersOut = <Map<String, dynamic>>[];

      for (final entry in _peerConnections.entries.toList()) {
        final otherUserId = entry.key;
        final pc = entry.value;

        try {
          // The ONE thing this poll never reported, and the thing that decides
          // how to read everything else it does report: whether the connection
          // is up at all. `bytesSent=0` and a media-source with no audioLevel
          // are what you see when the peer never connected — nothing is being
          // encoded — and that is indistinguishable from a broken microphone
          // unless the transport state is printed beside them.
          _log(
            'LINK to=$otherUserId conn=${pc.connectionState} '
            'ice=${pc.iceConnectionState} sig=${pc.signalingState}',
          );

          final stats = await pc.getStats();
          var sawCandidatePair = false;
          int? tx, rx;
          String? path;
          for (final r in stats) {
            if (report) {
              if (r.type == 'outbound-rtp' &&
                  (r.values['kind'] == 'audio' || r.values['mediaType'] == 'audio')) {
                tx = int.tryParse('${r.values['bytesSent']}');
              }
              if (r.type == 'inbound-rtp' &&
                  (r.values['kind'] == 'audio' || r.values['mediaType'] == 'audio')) {
                rx = int.tryParse('${r.values['bytesReceived']}');
              }
              if (r.type == 'candidate-pair' &&
                  r.values['state'] == 'succeeded' &&
                  r.values['nominated'] == true) {
                path = '${r.values['localCandidateType'] ?? '?'}/${r.values['remoteCandidateType'] ?? '?'}';
              }
            }
            // Which path ICE actually chose — host, srflx (STUN) or relay
            // (TURN). If nothing is ever nominated, the two ends never found a
            // route to each other and no amount of microphone work will help.
            if (r.type == 'candidate-pair' && r.values['state'] == 'succeeded') {
              sawCandidatePair = true;
              _log(
                'PATH to=$otherUserId nominated=${r.values['nominated']} '
                'rtt=${r.values['currentRoundTripTime']}',
              );
            }
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

          if (!sawCandidatePair) {
            _log('PATH to=$otherUserId — no succeeded candidate pair yet');
          }
          if (report) {
            peersOut.add({
              'id': otherUserId,
              'conn': '${pc.connectionState}'.split('.').last.replaceFirst('RTCPeerConnectionState', ''),
              'ice': '${pc.iceConnectionState}'.split('.').last.replaceFirst('RTCIceConnectionState', ''),
              'tx': tx,
              'rx': rx,
              if (path != null) 'path': path,
            });
          }
        } catch (_) {
          // ignore stats errors for some connections
        }
      }

      if (report && peersOut.isNotEmpty) {
        final up = peersOut.where((p) => p['conn'] == 'Connected').length;
        final rxing = peersOut.where((p) => (p['rx'] ?? 0) > 0).length;
        CrashReporter.event(
          'voice',
          'stats peers=${peersOut.length} up=$up rx>0=$rxing '
              'mic=${_listenOnly ? 'none' : (_isMicMuted ? 'muted' : 'live')}',
          data: {'peers': peersOut, 'speaker': AudioRoute.instance.speakerOn},
        );
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
          // A fresh announcement is a new session for them — possibly on a
          // different network — so a peer we had given up on gets another go.
          _rearmPeer(oid);
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

        // Who holds a mic. Absent on an older server, which means full mesh.
        final rawSpeakers = map['speakers'];
        if (rawSpeakers is List) {
          _speakers = rawSpeakers
              .map((e) => int.tryParse('$e') ?? 0)
              .where((id) => id != 0)
              .toSet();
        }

        debugPrint('👥 voice_users in room $_currentRoomId: $users '
            'speakers=${_speakers?.toList()}');

        // ✅ ADD THIS
        onVoiceUsersUpdated?.call(users);

        // Links that no longer need to exist: both ends stepped off the mics.
        // Dropped from the snapshot rather than on leave-seat, so both sides
        // prune from the same picture at the same time.
        for (final otherUserId in _peerConnections.keys.toList()) {
          if (!users.contains(otherUserId)) continue; // theirs to tear down
          if (_pairNeedsLink(otherUserId)) continue;
          _log('✂️ dropping listener↔listener link with $otherUserId');
          await _disposePeer(otherUserId, notify: true);
        }

        for (final otherUserId in users) {
          if (!_pairNeedsLink(otherUserId)) continue;
          // This is a server SNAPSHOT of who is in voice, broadcast again on
          // every join and leave in the room. Rebuilding a peer we have already
          // given up on from it would put the churn straight back: in a busy
          // room the snapshot arrives every few seconds, and each one would
          // tear down and re-create a connection that cannot come up.
          //
          // Nothing is lost by skipping them. A peer only becomes reachable
          // again after something changes on their side, and when it does their
          // client re-announces (`user_joined_voice`) or offers — both of which
          // re-arm them above.
          if (_unreachablePeers.contains(otherUserId)) {
            _log('skipping unreachable $otherUserId in voice_users snapshot');
            continue;
          }
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
        // They are trying again from their side. Whatever we concluded before,
        // answer it — refusing would leave them silent to us for good.
        _rearmPeer(fromUserId);
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
      }) {
    // Every caller that arrives while a build for this peer is running gets
    // that build's result. The first caller's `isInitiator` wins; a rebuild
    // decided later goes through `_recoverPeer`, which disposes first.
    final inFlight = _peerBuilds[otherUserId];
    if (inFlight != null) {
      debugPrint('⏳ Peer build already in flight for user $otherUserId');
      return inFlight;
    }
    final build = _buildPeerConnection(otherUserId, isInitiator: isInitiator);
    _peerBuilds[otherUserId] = build;
    return build.whenComplete(() {
      if (identical(_peerBuilds[otherUserId], build)) {
        _peerBuilds.remove(otherUserId);
      }
    });
  }

  Future<RTCPeerConnection> _buildPeerConnection(
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

      // The room may have been left while the native object was being made.
      // Storing it now would leave one live connection nobody will ever close.
      if (!_initialized || _currentRoomId == null) {
        _log('🚪 room left during peer build with $otherUserId — discarding');
        await _releasePeerConnection(pc, otherUserId);
        throw StateError('voice left during peer build');
      }

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
          CrashReporter.breadcrumb('peer $otherUserId connection FAILED');
          unawaited(_recoverPeer(otherUserId));
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _iceFailTimers.remove(otherUserId)?.cancel();
          _recoveryAttempts.remove(otherUserId);
        }
      };

      // Never overwrite a live connection silently: whatever was there is
      // closed AND freed first, or it lives on in native memory forever.
      final stray = _peerConnections[otherUserId];
      if (stray != null && !identical(stray, pc)) {
        _log('♻️ Replacing stray peer connection with $otherUserId');
        unawaited(_releasePeerConnection(stray, otherUserId));
      }
      _peerConnections[otherUserId] = pc;
      // The count is the point: this is a full mesh, and "how many native peer
      // connections did this phone hold when it died" is the first question any
      // report about the room has to answer.
      CrashReporter.breadcrumb(
        'peer +$otherUserId (live=${_peerConnections.length})',
      );

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
  /// Mute = RELEASE the microphone, not just disable the track.
  ///
  /// Disabling the track kept the capture (the AudioRecord) open, so Android's
  /// green microphone indicator stayed lit while the seat and the bottom bar
  /// both said "muted" — the client's screenshot, and a fair privacy complaint:
  /// an app that says it is not listening must not be holding the microphone.
  /// Unmute re-captures (~200ms), which is the right trade.
  ///
  /// The seat is kept (`_listenOnly` stays false) so the watchdog knows the
  /// user is still a speaker; it simply expects no capture while muted.
  Future<void> muteAudio() async {
    try {
      _isMicMuted = true;
      _stopMicWatchdog();
      if (_localStream != null) {
        await _releaseLocalMic();
        debugPrint('🔇 Microphone muted (capture released)');
      }
      // ✅ listening mode => speaker ON
      await _applyEchoSafeMode(talking: false);
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
  /// [muted] is the seat's own mute state. It used to be ignored: taking a
  /// seat that is muted still called `unmuteAudio`, so the room heard someone
  /// whose own UI showed a closed microphone. The seat decides.
  Future<void> goLive({bool muted = false}) async {
    if (!_initialized) return;
    _listenOnly = false;
    if (muted) {
      // A muted seat holds no capture at all (see muteAudio); the microphone
      // opens on the first unmute.
      _isMicMuted = true;
      await _applyEchoSafeMode(talking: false);
    } else {
      await unmuteAudio();
    }
    _log('goLive -> ${muted ? 'muted (no capture)' : 'speaking'}');
  }

  /// A2 — stop transmitting, keep listening. Called when the user leaves a seat.
  ///
  /// This used to only set `track.enabled = false`, which leaves the CAPTURE
  /// open: every listener in the room went on holding a live AudioRecord, just
  /// a muted one. That defeated the point of the listen-only join, and it is
  /// what produced the silent microphone — a capture held open and disabled for
  /// minutes gets reclaimed by the platform, and re-enabling it on the next
  /// goLive() yields a track that reports `enabled=true` and delivers
  /// `totalSamples=0.0`. Observed on device across exactly that sequence.
  ///
  /// So release it properly. goLive() captures fresh, which is both correct and
  /// what A2 promised: no microphone is open unless the user is on a seat.
  Future<void> goListenOnly() async {
    if (!_initialized) return;
    _listenOnly = true;
    // Off the seat: no capture to watch, and nothing to re-acquire. Leaving
    // these running would have us fighting another app for the microphone the
    // moment the user records a voice note somewhere else.
    _stopMicWatchdog();
    await _releaseLocalMic();
    await _applyEchoSafeMode(talking: false);
    _log('goListenOnly -> receive only');
  }

  /// Detach the microphone from every peer and hand it back to the platform.
  ///
  /// The senders are cleared first: a sender left pointing at a stopped track
  /// keeps the m-line alive and publishing silence, which is indistinguishable
  /// from a working microphone at the far end.
  Future<void> _releaseLocalMic() async {
    for (final entry in _peerConnections.entries.toList()) {
      try {
        for (final sender in await entry.value.getSenders()) {
          if (sender.track?.kind == 'audio') {
            await sender.replaceTrack(null);
          }
        }
      } catch (e) {
        _log('⚠️ could not detach mic from ${entry.key}: $e');
      }
    }

    final stream = _localStream;
    _localStream = null;
    _localAudioTrack = null;
    _isMicMuted = true;

    if (stream == null) return;
    for (final t in stream.getTracks()) {
      _detachTrackWatch(t);
      try {
        await t.stop();
      } catch (_) {
        // Already gone; nothing to release.
      }
    }
    try {
      await stream.dispose();
    } catch (_) {}
    _log('🎤 microphone released');
  }

  Future<void> unmuteAudio() async {
    try {
      // Opening the mic is the moment the user WILL notice a dead capture, so
      // check it here rather than let them talk into nothing: a seat taken while
      // muted holds an open-but-disabled capture, and the platform reclaims
      // those (an incoming call, another app recording) without telling us.
      if (!_initialized || _listenOnly) return; // no seat: nothing to open

      _isMicMuted = false;
      if (_localStream == null || _localAudioTrack == null) {
        // Mute released the capture (see muteAudio); open it again and put it
        // on every peer. This is also the recovery path after an interruption.
        await _ensureSpeakingStream();
      }
      final track = _localAudioTrack;
      if (track != null) {
        track.enabled = true;
        debugPrint('🔊 Microphone unmuted');
      }
      // ✅ talking mode => speaker OFF (earpiece) to kill echo
      await _applyEchoSafeMode(talking: true);
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
    for (final stream in _remoteStreams.values.toList()) {
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
      final audioSender = await _findAudioSender(pc);

      if (audioSender == null) {
        // No sender at all — this peer was built listen-only. Adding a track
        // changes the shape of the session, so it needs renegotiating.
        await pc.addTrack(track, _localStream!);
        _log('🎙️ Attached mic to reused peer $otherUserId — renegotiating');
        await _sendOffer(otherUserId);
        return;
      }

      // Compare by track ID, NOT object identity. flutter_webrtc returns a
      // fresh Dart wrapper from every getSenders() call, so `identical` was
      // never true and this replaced the track on EVERY reuse — pointless churn
      // on a live capture, and the device log showed the platform muting the
      // mic right after it.
      if (audioSender.track?.id == track.id) return;

      // A sender exists but points at a track we have since replaced. Swapping
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
    // Already given up on this one; only a real change re-arms it.
    if (_unreachablePeers.contains(otherUserId)) return;
    // An attempt is already scheduled — do not stack another on top of it.
    if (_recoveryTimers.containsKey(otherUserId)) return;

    _iceFailTimers.remove(otherUserId)?.cancel();

    final pc = _peerConnections[otherUserId];
    if (pc == null) return;

    final attempt = (_recoveryAttempts[otherUserId] ?? 0) + 1;

    if (attempt > _maxRecoveryAttempts) {
      _giveUpOnPeer(otherUserId);
      return;
    }

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

      // Attempts 3..5 rebuild, each after a longer wait. The wait is the point:
      // a rebuild that fails for a network reason will fail again immediately,
      // and hammering it is what turned one unreachable peer into a busy loop.
      final delay = _rebuildBackoff[
          (attempt - 3).clamp(0, _rebuildBackoff.length - 1)];
      _log('🔁 Rebuild #$attempt with $otherUserId in ${delay.inSeconds}s');
      CrashReporter.breadcrumb('peer $otherUserId rebuild #$attempt');
      _recoveryTimers[otherUserId] = Timer(delay, () async {
        _recoveryTimers.remove(otherUserId);
        if (_currentRoomId == null || _unreachablePeers.contains(otherUserId)) {
          return;
        }
        // It may have healed while we waited — ICE does that.
        final live = _peerConnections[otherUserId];
        if (live != null && _isPeerUsable(live)) {
          _log('✅ $otherUserId healed on its own — rebuild cancelled');
          _recoveryAttempts.remove(otherUserId);
          return;
        }
        _restarting.add(otherUserId);
        try {
          await _disposePeer(otherUserId);
          await _createPeerConnection(otherUserId, isInitiator: drives);
        } catch (e) {
          _log('❌ rebuild of $otherUserId failed: $e');
        } finally {
          _restarting.remove(otherUserId);
        }
      });
    } catch (e) {
      _log('❌ recoverPeer error: $e');
    } finally {
      _restarting.remove(otherUserId);
    }
  }

  /// Stop chasing a peer that will not connect, and free what it was holding.
  ///
  /// This is not a failure to hide: with no TURN server two users on mobile data
  /// have no path to each other at all, and an app that retries forever just
  /// drains the phone while staying silent. Report it once, release the
  /// connection, and wait for something to change.
  void _giveUpOnPeer(int otherUserId) {
    if (!_unreachablePeers.add(otherUserId)) return;
    _recoveryTimers.remove(otherUserId)?.cancel();
    _iceFailTimers.remove(otherUserId)?.cancel();
    _recoveryAttempts.remove(otherUserId);
    _log('⛔ giving up on $otherUserId after $_maxRecoveryAttempts attempts');
    CrashReporter.breadcrumb('peer $otherUserId unreachable — gave up');
    unawaited(_disposePeer(otherUserId, notify: true));
    onPeerUnreachable?.call(otherUserId);
  }

  /// Let a peer be retried again, because something that could change the
  /// outcome has happened: the socket came back, or that user re-announced
  /// themselves in voice (a new session, possibly on a different network).
  void _rearmPeer(int otherUserId) {
    if (_unreachablePeers.remove(otherUserId)) {
      _log('♻️ re-arming previously unreachable peer $otherUserId');
    }
    _recoveryAttempts.remove(otherUserId);
    _recoveryTimers.remove(otherUserId)?.cancel();
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
      await _releasePeerConnection(pc, otherUserId);
    }

    final renderer = _remoteRenderers.remove(otherUserId);
    if (renderer != null) {
      try {
        await renderer.dispose();
      } catch (_) {}
      _audioRenderers.remove(renderer);
    }
    await _releaseRemoteStream(otherUserId);

    if (notify) onRemoteStreamRemoved?.call(otherUserId);
  }

  /// Close AND free one peer connection.
  ///
  /// `close()` alone was the single largest leak in the app. In the plugin the
  /// two calls do different things:
  ///
  ///   close()   -> peerConnection.close()                  // stops the media
  ///   dispose() -> close() + peerConnection.dispose()       // frees the object
  ///                + eventChannel.setStreamHandler(null)    // + drops the
  ///                                                         //   observer entry
  ///
  /// So every peer this app had ever built stayed alive in native memory for the
  /// life of the process, with its own event channel and its entry in the
  /// plugin's observer map. In a full mesh that is one leak per member per room,
  /// and with the ICE-failure rebuild loop it was one per failed attempt —
  /// megabytes a minute until Android killed the process, which is the
  /// "التطبيق يقفل ويرجع للشاشة الرئيسية بعد حوالي دقيقة" report.
  ///
  /// It also kept the plugin's observer map non-empty forever, and the plugin
  /// only calls `AudioSwitchManager.stop()` when that map empties — so the phone
  /// stayed in MODE_IN_COMMUNICATION holding audio focus even after leaving the
  /// room. Freeing the peers is what lets the audio mode go back to normal.
  Future<void> _releasePeerConnection(
    RTCPeerConnection pc,
    int otherUserId,
  ) async {
    // Detach the callbacks first: a closing connection still delivers state
    // changes, and onConnectionState -> _recoverPeer would rebuild the peer we
    // are in the middle of throwing away.
    try {
      pc.onTrack = null;
      pc.onIceCandidate = null;
      pc.onIceConnectionState = null;
      pc.onConnectionState = null;
      pc.onSignalingState = null;
      pc.onRenegotiationNeeded = null;
      pc.onAddStream = null;
      pc.onRemoveStream = null;
    } catch (_) {}

    try {
      await pc.close();
    } catch (e) {
      _log('⚠️ closing peer $otherUserId: $e');
    }
    try {
      await pc.dispose();
    } catch (e) {
      _log('⚠️ freeing peer $otherUserId: $e');
    }
    CrashReporter.breadcrumb(
      'peer -$otherUserId freed (live=${_peerConnections.length})',
    );
  }

  /// Hand back the remote stream a peer was delivering.
  ///
  /// What actually frees a remote stream is disposing the peer connection that
  /// owns it — verified in the plugin: `trackDispose` and `streamDispose` look
  /// the id up in the LOCAL track/stream maps and log "is null" for anything
  /// remote, so on Android these calls are a safe no-op. They are made anyway
  /// because the Dart reference has to go either way, the iOS side does track
  /// remote streams, and a released peer with its stream still in
  /// `_remoteStreams` is how a stale stream ends up handed to the UI.
  Future<void> _releaseRemoteStream(int otherUserId) async {
    final stream = _remoteStreams.remove(otherUserId);
    if (stream == null) return;
    try {
      for (final t in stream.getTracks()) {
        try {
          await t.stop();
        } catch (_) {}
      }
      await stream.dispose();
    } catch (e) {
      _log('⚠️ freeing remote stream of $otherUserId: $e');
    }
  }

  /// Drop the entire mesh, keeping the local microphone. Used when the socket
  /// comes back: every connection negotiated over the old one is unrecoverable,
  /// because the signalling path that could have repaired it is gone.
  Future<void> _teardownAllPeers() async {
    for (final t in _recoveryTimers.values.toList()) {
      t.cancel();
    }
    _recoveryTimers.clear();
    for (final otherUserId in _peerConnections.keys.toList()) {
      await _disposePeer(otherUserId, notify: true);
    }
    _recoveryAttempts.clear();
    _restarting.clear();
    // The transport is new, so every previous verdict is void: a peer that had
    // no path over the old connection may well have one now.
    _unreachablePeers.clear();
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

      for (final t in _iceFailTimers.values.toList()) {
        t.cancel();
      }
      _iceFailTimers.clear();
      _pendingCandidates.clear();
      _remoteDescriptionSet.clear();
      _makingOffer.clear();
      _restarting.clear();
      _recoveryAttempts.clear();
      for (final t in _recoveryTimers.values.toList()) {
        t.cancel();
      }
      _recoveryTimers.clear();
      _unreachablePeers.clear();
      _speakers = null;
      _listenOnly = false;

      _statsTimer?.cancel();
      _statsTimer = null;
      _stopMicWatchdog();
      _unwatchAppLifecycle();

      // Stop VAD timer
      _vadEnabled = false;
      _vadTimer?.cancel();
      _vadTimer = null;
      _vadSpeaking = false;
      _vadQuietTicks = 0;
      _audioLevel = 0.0;

      // Close AND FREE every peer connection. `close()` on its own leaves the
      // native object, its event channel and its entry in the plugin's observer
      // map alive for the life of the process — see [_releasePeerConnection].
      // Leaving a room used to leak the whole mesh, every time.
      final peers = Map<int, RTCPeerConnection>.from(_peerConnections);
      _peerConnections.clear();
      for (final entry in peers.entries) {
        await _releasePeerConnection(entry.value, entry.key);
      }

      // The remote streams those peers were delivering go with them.
      for (final id in _remoteStreams.keys.toList()) {
        await _releaseRemoteStream(id);
      }

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

      // Stop AND free the local stream. Stopping the tracks releases the
      // microphone; the stream object itself is native too and needs disposing,
      // or one is left behind per room session.
      final local = _localStream;
      _localStream = null;
      _localAudioTrack = null;
      if (local != null) {
        for (final track in local.getTracks()) {
          _detachTrackWatch(track);
          try {
            await track.stop();
          } catch (_) {}
        }
        try {
          await local.dispose();
        } catch (e) {
          debugPrint('⚠️ freeing local stream: $e');
        }
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

/// Turns Flutter's lifecycle callbacks into "is the app in front?".
///
/// `inactive` is deliberately ignored: on Android it fires for a pulled-down
/// notification shade and other momentary things, and treating those as leaving
/// the app would slow a recovery the user is waiting on.
class _AudioLifecycleWatcher extends WidgetsBindingObserver {
  _AudioLifecycleWatcher(this._onChange);

  final void Function(bool foreground) _onChange;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _onChange(true);
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _onChange(false);
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }
}
