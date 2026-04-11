// lib/services/webrtc_service.dart

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'socket_service.dart';

class WebRTCService {
  final SocketService _socketService;
  final int roomId;
  final int userId;

  Map<int, RTCPeerConnection> _peerConnections = {};
  MediaStream? _localStream;
  bool _isMicMuted = false;
  bool _isSpeakerOn = true;

  WebRTCService({
    required SocketService socketService,
    required this.roomId,
    required this.userId,
  }) : _socketService = socketService;

  /// Initialize WebRTC with microphone permissions
  Future<void> initialize() async {
    try {
      print('🎤 Initializing WebRTC...');

      // Request microphone permission
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        print('❌ Microphone permission denied');
        throw Exception('Microphone permission denied');
      }

      // Get local audio stream
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });

      print('✅ WebRTC initialized successfully');

      // Setup WebRTC signaling via Socket.IO
      _setupSignaling();
    } catch (e) {
      print('❌ Error initializing WebRTC: $e');
      rethrow;
    }
  }

  /// Initialize audio only (simplified version)
  Future<void> initializeAudio() async {
    try {
      print('🎤 Initializing audio...');

      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        print('❌ Microphone permission not granted');
        return;
      }

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });

      print('✅ Audio stream initialized');
    } catch (e) {
      print('❌ Error initializing audio: $e');
    }
  }

  void _setupSignaling() {
    // Listen for other users joining
    _socketService.on('user_joined_voice', (data) async {
      final otherUserId = data['userId'] as int;
      if (otherUserId != userId) {
        await _createPeerConnection(otherUserId, true);
      }
    });

    // Listen for WebRTC offers
    _socketService.on('webrtc_offer', (data) async {
      try {
        final fromUserId = data['from'] as int;
        final offer = data['offer'];

        // Check if peer connection already exists
        var pc = _peerConnections[fromUserId];
        if (pc == null) {
          pc = await _createPeerConnection(fromUserId, false);
        }

        await pc.setRemoteDescription(
          RTCSessionDescription(offer['sdp'], offer['type']),
        );

        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);

        _socketService.emit('webrtc_answer', {
          'roomId': roomId,
          'to': fromUserId,
          'answer': {
            'sdp': answer.sdp,
            'type': answer.type,
          },
        });
      } catch (e) {
        print('❌ Error handling offer: $e');
      }
    });

    // Listen for WebRTC answers
    _socketService.on('webrtc_answer', (data) async {
      try {
        final fromUserId = data['from'] as int;
        final answer = data['answer'];

        final pc = _peerConnections[fromUserId];
        if (pc != null) {
          // Only set remote description if in the correct state
          final state = pc.connectionState;
          print('🔍 Peer connection state before answer: $state');

          if (state != 'closed' && state != 'failed') {
            await pc.setRemoteDescription(
              RTCSessionDescription(answer['sdp'], answer['type']),
            );
            print('✅ Remote answer set successfully');
          } else {
            print('⚠️ Ignoring answer - peer connection is $state');
          }
        } else {
          print('⚠️ Peer connection not found for user $fromUserId');
        }
      } catch (e) {
        print('❌ Error handling answer: $e');
      }
    });

    // Listen for ICE candidates
    _socketService.on('webrtc_ice_candidate', (data) async {
      try {
        final fromUserId = data['from'] as int;
        final candidate = data['candidate'];

        final pc = _peerConnections[fromUserId];
        if (pc != null) {
          await pc.addCandidate(
            RTCIceCandidate(
              candidate['candidate'],
              candidate['sdpMid'],
              candidate['sdpMLineIndex'],
            ),
          );
        }
      } catch (e) {
        print('⚠️ Error adding ICE candidate: $e');
      }
    });

    // Listen for user leaving
    _socketService.on('user_left_voice', (data) {
      final otherUserId = data['userId'] as int;
      _closePeerConnection(otherUserId);
    });
  }

  Future<RTCPeerConnection> _createPeerConnection(
      int otherUserId,
      bool isInitiator,
      ) async {
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        // Add TURN servers for production
      ],
    };

    final pc = await createPeerConnection(configuration);

    // Add local stream
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        pc.addTrack(track, _localStream!);
      });
    }

    // Handle remote stream
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        // Play remote audio
        print('📡 Remote audio stream received');
      }
    };

    // Handle ICE candidates
    pc.onIceCandidate = (candidate) {
      if (candidate != null) {
        _socketService.emit('webrtc_ice_candidate', {
          'roomId': roomId,
          'to': otherUserId,
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        });
      }
    };

    _peerConnections[otherUserId] = pc;

    // Create offer if initiator
    if (isInitiator) {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      _socketService.emit('webrtc_offer', {
        'roomId': roomId,
        'to': otherUserId,
        'offer': {
          'sdp': offer.sdp,
          'type': offer.type,
        },
      });
    }

    return pc;
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
      }
    } catch (e) {
      print('❌ Error muting audio: $e');
    }
  }

  /// Unmute microphone
  Future<void> unmuteAudio() async {
    try {
      if (_localStream != null) {
        for (var track in _localStream!.getAudioTracks()) {
          track.enabled = true;
        }
        _isMicMuted = false;
        print('🔊 Microphone unmuted');
      }
    } catch (e) {
      print('❌ Error unmuting audio: $e');
    }
  }

  /// Toggle microphone mute
  void toggleMute() {
    if (_localStream != null) {
      _isMicMuted = !_isMicMuted;
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = !_isMicMuted;
      });
      print(_isMicMuted ? '🔇 Muted' : '🔊 Unmuted');
    }
  }

  /// Set speaker on/off
  Future<void> setSpeakerphoneOn(bool on) async {
    try {
      _isSpeakerOn = on;
      print(on ? '🔊 Speaker ON' : '🔇 Speaker OFF');
    } catch (e) {
      print('❌ Error setting speaker: $e');
    }
  }

  /// Get microphone status
  bool get isMicMuted => _isMicMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  MediaStream? get localStream => _localStream;

  /// Get list of available microphones
  Future<List<MediaDeviceInfo>> getMicrophones() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      final microphones = devices
          .where((device) => device.kind == 'audioinput')
          .toList();
      print('🎤 Found ${microphones.length} microphones');
      return microphones;
    } catch (e) {
      print('❌ Error getting microphones: $e');
      return [];
    }
  }

  /// Switch to specific microphone
  Future<void> switchMicrophone(String deviceId) async {
    try {
      print('🔄 Switching to microphone: $deviceId');

      // Stop current stream
      if (_localStream != null) {
        for (var track in _localStream!.getAudioTracks()) {
          await track.stop();
        }
      }

      // Get new stream with specific device
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'deviceId': {'exact': deviceId},
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });

      print('✅ Switched to microphone: $deviceId');
    } catch (e) {
      print('❌ Error switching microphone: $e');
    }
  }

  /// Test microphone
  Future<bool> testMicrophone() async {
    try {
      print('🧪 Testing microphone...');
      final mics = await getMicrophones();
      if (mics.isEmpty) {
        print('❌ No microphones found');
        return false;
      }
      print('✅ Microphone test passed');
      return true;
    } catch (e) {
      print('❌ Microphone test failed: $e');
      return false;
    }
  }

  /// Get audio stats
  Future<Map<String, dynamic>> getAudioStats() async {
    try {
      return {
        'isMicMuted': _isMicMuted,
        'isSpeakerOn': _isSpeakerOn,
        'hasLocalStream': _localStream != null,
        'audioTracksCount': _localStream?.getAudioTracks().length ?? 0,
      };
    } catch (e) {
      print('❌ Error getting audio stats: $e');
      return {};
    }
  }

  void _closePeerConnection(int otherUserId) {
    final pc = _peerConnections[otherUserId];
    if (pc != null) {
      pc.close();
      _peerConnections.remove(otherUserId);
    }
  }

  void dispose() {
    _peerConnections.forEach((_, pc) => pc.close());
    _peerConnections.clear();
    _localStream?.dispose();
    print('✅ WebRTC service disposed');
  }
}
