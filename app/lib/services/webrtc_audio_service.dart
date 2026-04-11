import 'dart:async';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'socket_service.dart';


/// Complete WebRTC Audio Service with Peer Connections
/// Handles voice chat between multiple users in a room
class WebRTCAudioService {
  static final WebRTCAudioService _instance = WebRTCAudioService._internal();

  factory WebRTCAudioService() {
    return _instance;
  }

  WebRTCAudioService._internal();

  void _log(String msg) {
    print('🎤 MIC_DEBUG | $msg');
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

  // Voice Activity Detection (VAD)
  Timer? _vadTimer;
  double _audioLevel = 0.0;
  int _silenceCounter = 0;
  bool _vadEnabled = false;
  final int _silenceThreshold = 5; // 500ms of silence
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

    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
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
      _log('Track enabled=${_localAudioTrack!.enabled}');
    }
  }

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

    if (Platform.isAndroid) {
      await _forceAndroidVoiceRoute();
    }

  }

  Future<void> _attachLocalTrackToAllPeers() async {
    if (_localStream == null) return;

    final track = _localStream!.getAudioTracks().isNotEmpty
        ? _localStream!.getAudioTracks().first
        : null;
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

  Future<void> _renegotiateAllPeers() async {
    for (final entry in _peerConnections.entries) {
      final otherUserId = entry.key;
      final pc = entry.value;

      try {
        // create new offer (unified-plan renegotiation)
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);

        _socketService.emit('webrtc_offer', {
          'roomId': _currentRoomId,
          'to': otherUserId,
          'from': _currentUserId,
          'offer': {'sdp': offer.sdp, 'type': offer.type},
        });

        _log('🔁 Renegotiation offer sent to $otherUserId');
      } catch (e) {
        _log('⚠️ renegotiate failed to $otherUserId: $e');
      }
    }
  }

  Future<void> _forceAndroidVoiceRoute() async {
    if (!Platform.isAndroid) return;
    await _applyEchoSafeMode(talking: false); // default: speaker ON only if listening
  }


  Future<void> _applyAndroidAudioRoute({required bool speakerOn}) async {
    if (!Platform.isAndroid) return;
    try {
      await Helper.setSpeakerphoneOn(speakerOn);
      _log('Android route -> speakerOn=$speakerOn');
    } catch (e) {
      _log('⚠️ _applyAndroidAudioRoute failed: $e');
    }
  }

  /// When user is TALKING: use earpiece (speaker OFF) to avoid echo.
  /// When user is LISTENING: use speaker ON.
  Future<void> _applyEchoSafeMode({required bool talking}) async {
    if (!Platform.isAndroid) return;

    // talking => speaker OFF (earpiece), listening => speaker ON
    await _applyAndroidAudioRoute(speakerOn: !talking);
  }


  /// Initialize WebRTC for a specific room and user
  Future<void> initialize({
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
      _log('initialize skipped (already initialized for same room/user)');
      return;
    }
    _initialized = true;

// ✅ On socket reconnect, rejoin voice + refresh voice users (so signaling resumes)
    await _reconnectSub?.cancel();
    _reconnectSub = _socketService.reconnectStream.listen((_) {
      if (_currentRoomId == null || _currentUserId == null) return;

      _log('🔁 socket reconnected -> rejoin voice + refresh users');
      _socketService.emit('user_joined_voice', {
        'roomId': _currentRoomId,
        'userId': _currentUserId,
      });
      _socketService.emit('get_voice_users', {'roomId': _currentRoomId});
    });


    if (!listenOnly) {
      _localStream = await navigator.mediaDevices.getUserMedia({
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


      final tracks = _localStream!.getAudioTracks();
      _log('Local stream created. audioTracks=${tracks.length}');
      for (final t in tracks) {
        t.enabled = true;
        _log('Track id=${t.id} kind=${t.kind} enabled=${t.enabled}');
      }
      await _forceAndroidVoiceRoute();


    }
    else {
      _localStream = null;
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
      if (_localStream != null) {
        for (final t in _localStream!.getTracks()) {
          try { await t.stop(); } catch (_) {}
        }
        _localStream = null;
      }

      // close all peer connections
      for (final pc in _peerConnections.values) {
        try { await pc.close(); } catch (_) {}
      }
      _peerConnections.clear();

      // cleanup remote streams/renderers
      for (final r in _remoteRenderers.values) {
        try { await r.dispose(); } catch (_) {}
      }
      _remoteRenderers.clear();
      _remoteStreams.clear();
      _audioRenderers.clear();

      _initialized = false;
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
          print('⚠️ user_joined_voice missing userId: $map');
          return;
        }

        if (oid != _currentUserId) {
          final isInitiator = _shouldInitiateWith(oid);
          print('👤 User $oid joined voice chat (initiator=$isInitiator)');
          await _createPeerConnection(oid, isInitiator: isInitiator);
        }

      } catch (e) {
        print('❌ Error handling user_joined_voice: $e');
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

        print('👥 voice_users in room $_currentRoomId: $users');

        // ✅ ADD THIS
        onVoiceUsersUpdated?.call(users);

        for (final otherUserId in users) {
          final isInitiator = _shouldInitiateWith(otherUserId);
          await _createPeerConnection(otherUserId, isInitiator: isInitiator);
        }

      } catch (e) {
        print('❌ Error handling voice_users: $e');
      }
    });

    // Listen for WebRTC offers
    _socketService.on('webrtc_offer', (data) async {
      try {
        final fromUserId = data['from'] as int;
        final offer = Map<String, dynamic>.from(data['offer'] as Map);

        print('📨 Received offer from user $fromUserId');

        final pc = await _createPeerConnection(fromUserId, isInitiator: false);

        // Set remote description (offer)
        await pc.setRemoteDescription(
          RTCSessionDescription(offer['sdp'] as String, offer['type'] as String),
        );

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

        print('📤 Sent answer to user $fromUserId');
      } catch (e) {
        print('❌ Error handling webrtc_offer: $e');
        onError?.call('Error handling offer: $e');
      }
    });

    // Listen for WebRTC answers
    _socketService.on('webrtc_answer', (data) async {
      try {
        final fromUserId = data['from'] as int;
        final answer = Map<String, dynamic>.from(data['answer'] as Map);

        print('📨 Received answer from user $fromUserId');

        final pc = _peerConnections[fromUserId];
        if (pc != null) {
          await pc.setRemoteDescription(
            RTCSessionDescription(answer['sdp'] as String, answer['type'] as String),
          );
          print('✅ Set remote description for user $fromUserId');
        }
      } catch (e) {
        print('❌ Error handling webrtc_answer: $e');
        onError?.call('Error handling answer: $e');
      }
    });

    // Listen for ICE candidates
    _socketService.on('webrtc_ice_candidate', (data) async {
      try {
        final fromUserId = data['from'] as int;
        final candidate = Map<String, dynamic>.from(data['candidate'] as Map);

        final pc = _peerConnections[fromUserId];
        if (pc != null) {
          await pc.addCandidate(
            RTCIceCandidate(
              candidate['candidate'] as String,
              candidate['sdpMid'] as String?,
              candidate['sdpMLineIndex'] as int?,
            ),
          );
        }
      } catch (e) {
        print('⚠️ Error adding ICE candidate: $e');
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

        await unmuteAudio();

        // ⭐ هنا بالظبط تضيف السطرين
        await _attachLocalTrackToAllPeers();
        await _renegotiateAllPeers();

      } catch (e) {
        _log('❌ approveMic handler error: $e');
      }
    });


    // Listen for user leaving voice chat
    _socketService.on('user_left_voice', (data) {
      try {
        final otherUserId = data['userId'] as int;
        print('👤 User $otherUserId left voice chat');
        _closePeerConnection(otherUserId);
      } catch (e) {
        print('❌ Error handling user_left_voice: $e');
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
      // Check if connection already exists
      if (_peerConnections.containsKey(otherUserId)) {
        print('⚠️ Peer connection already exists for user $otherUserId');
        return _peerConnections[otherUserId]!;
      }

      print('🔗 Creating peer connection with user $otherUserId (initiator: $isInitiator)');

      // ICE servers configuration with STUN/TURN and optimizations
      final configuration = <String, dynamic>{
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {'urls': 'stun:stun2.l.google.com:19302'},
          {'urls': 'stun:stun3.l.google.com:19302'},
          {'urls': 'stun:stun4.l.google.com:19302'},
        ],
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
            print('⚠️ addTrack failed for user $otherUserId: $e');
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
        print('⚠️ Could not set extra audio configuration: $e');
      }

      // Handle remote tracks (audio)
      pc.onTrack = (RTCTrackEvent event) {
        try {
          if (event.streams.isEmpty) return;

          final remoteStream = event.streams[0];
          _remoteStreams[otherUserId] = remoteStream;

          for (final t in remoteStream.getAudioTracks()) {
            t.enabled = true;
          }

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
          print('⚠️ Failed sending ICE candidate to $otherUserId: $e');
        }
      };

      // ICE connection state changes (KEEP ONLY ONE HANDLER — the restart one)
      pc.onIceConnectionState = (RTCIceConnectionState state) {
        print('❄️ ICE connection state with user $otherUserId: $state');

        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          _restartPeer(otherUserId);
          return;
        }

        if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          _iceFailTimers[otherUserId]?.cancel();
          _iceFailTimers[otherUserId] = Timer(const Duration(seconds: 4), () {
            _restartPeer(otherUserId);
          });
          return;
        }

        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _iceFailTimers[otherUserId]?.cancel();
          _iceFailTimers.remove(otherUserId);
        }
      };

      // Overall connection state (debug)
      pc.onConnectionState = (RTCPeerConnectionState state) {
        print('🔄 Connection state with user $otherUserId: $state');
      };

      _peerConnections[otherUserId] = pc;

      // Create offer if initiator
      if (isInitiator) {
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);

        _socketService.emit('webrtc_offer', {
          'roomId': _currentRoomId,
          'to': otherUserId,
          'from': _currentUserId,
          'offer': {
            'sdp': offer.sdp,
            'type': offer.type,
          },
        });

        print('📤 Sent offer to user $otherUserId');
      }

      startMicStats();
      return pc;
    } catch (e) {
      print('❌ Error creating peer connection: $e');
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
        print('🔇 Microphone muted');

        // ✅ listening mode => speaker ON
        await _applyEchoSafeMode(talking: false);
      }
    } catch (e) {
      print('❌ Error muting audio: $e');
      onError?.call('Error muting audio: $e');
    }
  }

  Future<void> unmuteAudio() async {
    try {
      if (_localStream != null) {
        for (var track in _localStream!.getAudioTracks()) {
          track.enabled = true;
        }
        _isMicMuted = false;
        print('🔊 Microphone unmuted');

        // ✅ talking mode => speaker OFF (earpiece) to kill echo
        await _applyEchoSafeMode(talking: true);
      }
    } catch (e) {
      print('❌ Error unmuting audio: $e');
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

  /// Set speaker on/off
  Future<void> setSpeakerphoneOn(bool on) async {
    _isSpeakerOn = on;

    // Android route
    if (Platform.isAndroid) {
      await _applyAndroidAudioRoute(speakerOn: on);
    }

    // iOS route (also works with Helper)
    if (Platform.isIOS) {
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

  Future<void> _restartPeer(int otherUserId) async {
    try {
      _log('🔁 Restarting peer connection with user $otherUserId');

      // Close old one
      final old = _peerConnections[otherUserId];
      try {
        await old?.close();
      } catch (_) {}

      _peerConnections.remove(otherUserId);

      // Remove renderer/stream to force rebuild
      final renderer = _remoteRenderers.remove(otherUserId);
      if (renderer != null) {
        try { await renderer.dispose(); } catch (_) {}
        _audioRenderers.remove(renderer);
      }
      _remoteStreams.remove(otherUserId);

      // Create new PC
      final initiator = _shouldInitiateWith(otherUserId);
      final pc = await _createPeerConnection(otherUserId, isInitiator: initiator);

      // If we are initiator and PC was created without offer (rare), force renegotiate
      if (initiator) {
        try {
          final offer = await pc.createOffer();
          await pc.setLocalDescription(offer);
          _socketService.emit('webrtc_offer', {
            'roomId': _currentRoomId,
            'to': otherUserId,
            'from': _currentUserId,
            'offer': {'sdp': offer.sdp, 'type': offer.type},
          });
          _log('📤 Re-offer sent to $otherUserId after restart');
        } catch (e) {
          _log('⚠️ Re-offer failed after restart: $e');
        }
      }
    } catch (e) {
      _log('❌ restartPeer error: $e');
    }
  }


  /// Close peer connection with specific user
  void _closePeerConnection(int otherUserId) {
    try {
      final pc = _peerConnections[otherUserId];
      if (pc != null) {
        pc.close();
        _peerConnections.remove(otherUserId);
        print('✅ Closed peer connection with user $otherUserId');
      }

      // Dispose remote renderer
      final renderer = _remoteRenderers[otherUserId];
      if (renderer != null) {
        renderer.dispose();
        _remoteRenderers.remove(otherUserId);
        _audioRenderers.remove(renderer);
      }

      // Remove remote stream
      _remoteStreams.remove(otherUserId);

      onRemoteStreamRemoved?.call(otherUserId);
    } catch (e) {
      print('❌ Error closing peer connection: $e');
    }
  }

  /// Dispose all resources
  Future<void> dispose() async {
    try {
      print('🧹 Disposing WebRTC service...');

      _initialized = false;

      await _reconnectSub?.cancel();
      _reconnectSub = null;

      for (final t in _iceFailTimers.values) {
        t.cancel();
      }
      _iceFailTimers.clear();

      _statsTimer?.cancel();
      _statsTimer = null;

      // Stop VAD timer
      _vadTimer?.cancel();
      _vadTimer = null;

      // Close all peer connections
      for (var entry in _peerConnections.entries) {
        try {
          entry.value.close();
        } catch (e) {
          print('⚠️ Error closing peer connection: $e');
        }
      }
      _peerConnections.clear();

      // Dispose all renderers
      for (var renderer in _audioRenderers) {
        try {
          await renderer.dispose();
        } catch (e) {
          print('⚠️ Error disposing renderer: $e');
        }
      }
      _audioRenderers.clear();
      _remoteRenderers.clear();

      // Stop local stream
      if (_localStream != null) {
        for (var track in _localStream!.getTracks()) {
          await track.stop();
        }
        _localStream = null;
      }

      _socketService.emit('user_left_voice', {
        'roomId': _currentRoomId,
        'userId': _currentUserId,
      });

      print('✅ WebRTC service disposed');
    } catch (e) {
      print('❌ Error disposing WebRTC: $e');
    }
  }

  /// Enable Voice Activity Detection (VAD)
  void enableVAD() {
    if (_vadEnabled) return;
    _vadEnabled = true;
    _startVoiceActivityDetection();
    print('✅ VAD enabled');
  }

  /// Disable Voice Activity Detection
  void disableVAD() {
    _vadEnabled = false;
    _vadTimer?.cancel();
    _vadTimer = null;
    print('❌ VAD disabled');
  }

  /// Start monitoring voice activity
  void _startVoiceActivityDetection() {
    _vadTimer?.cancel();
    _vadTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!_vadEnabled || _localStream == null) {
        timer.cancel();
        return;
      }

      try {
        // Simple silence detection based on track state
        // In production, use proper audio level analysis
        bool isSpeaking = !_isMicMuted;

        // Simulate audio level detection (simplified)
        if (_audioLevel < 0.01) {
          _silenceCounter++;
          if (_silenceCounter >= _silenceThreshold && !_isMicMuted) {
            // Auto-mute after silence threshold
            await muteAudio();
            onVoiceActivityChanged?.call(false);
            print('🔇 Auto-muted due to silence');
          }
        } else {
          _silenceCounter = 0;
          if (_isMicMuted) {
            // Auto-unmute when speaking
            await unmuteAudio();
            onVoiceActivityChanged?.call(true);
            print('🔊 Auto-unmuted due to voice activity');
          }
        }
      } catch (e) {
        print('⚠️ VAD error: $e');
      }
    });
  }

  /// Update audio level (call this from audio analysis)
  void updateAudioLevel(double level) {
    _audioLevel = level;
  }

  /// Enable Push-to-Talk mode
  void enablePTT() {
    _pttMode = true;
    _isPttActive = false;
    // Auto-mute when enabling PTT
    muteAudio();
    print('✅ PTT mode enabled');
  }

  /// Disable Push-to-Talk mode
  void disablePTT() {
    _pttMode = false;
    _isPttActive = false;
    print('❌ PTT mode disabled');
  }

  /// Start talking (PTT press)
  Future<void> startPTT() async {
    if (!_pttMode) return;
    _isPttActive = true;
    await unmuteAudio();
    print('🎯 PTT activated - speaking');
  }

  /// Stop talking (PTT release)
  Future<void> stopPTT() async {
    if (!_pttMode) return;
    _isPttActive = false;
    await muteAudio();
    print('🎯 PTT deactivated - muted');
  }

  /// Check if PTT mode is enabled
  bool get isPTTMode => _pttMode;
  bool get isPTTActive => _isPttActive;
}
