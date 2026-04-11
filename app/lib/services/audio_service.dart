import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

/// Fixed Audio Service for microphone and speaker control
/// Handles basic audio operations with proper initialization
class AudioService {
  static final AudioService _instance = AudioService._internal();

  factory AudioService() {
    return _instance;
  }

  AudioService._internal();

  MediaStream? _localStream;
  bool _isMicMuted = false;
  bool _isSpeakerOn = true;
  bool _isInitialized = false;

  /// Initialize audio stream with proper error handling
  Future<bool> initializeAudio() async {
    if (_isInitialized) {
      print('⚠️ Audio already initialized');
      return true;
    }

    try {
      print('🎤 Initializing audio...');

      // Request microphone permission
      final status = await Permission.microphone.request();

      if (!status.isGranted) {
        print('❌ Microphone permission not granted: $status');

        if (status.isPermanentlyDenied) {
          print('⚠️ Permission permanently denied. Please enable in settings.');
        }

        return false;
      }

      print('✅ Microphone permission granted');

      // Get local audio stream with optimized settings
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'sampleRate': 48000,  // High quality audio
          'channelCount': 1,     // Mono for voice chat
        },
        'video': false,
      });

      if (_localStream == null) {
        print('❌ Failed to get media stream');
        return false;
      }

      final audioTracks = _localStream!.getAudioTracks();

      if (audioTracks.isEmpty) {
        print('❌ No audio tracks in stream');
        return false;
      }

      _isInitialized = true;
      print('✅ Audio initialized successfully');
      print('📊 Audio tracks: ${audioTracks.length}');

      // Log track details
      for (var track in audioTracks) {
        print('🎙️ Track: ${track.label}, enabled: ${track.enabled}');
      }

      return true;
    } catch (e) {
      print('❌ Error initializing audio: $e');
      print('Stack trace: ${StackTrace.current}');
      _isInitialized = false;
      return false;
    }
  }

  /// Mute microphone
  Future<void> muteAudio() async {
    if (_localStream == null) {
      print('⚠️ No local stream to mute');
      return;
    }

    try {
      final tracks = _localStream!.getAudioTracks();

      if (tracks.isEmpty) {
        print('⚠️ No audio tracks to mute');
        return;
      }

      for (var track in tracks) {
        track.enabled = false;
        print('🔇 Track ${track.label} disabled');
      }

      _isMicMuted = true;
      print('🔇 Microphone muted');
    } catch (e) {
      print('❌ Error muting: $e');
    }
  }

  /// Unmute microphone
  Future<void> unmuteAudio() async {
    if (_localStream == null) {
      print('⚠️ No local stream to unmute');
      return;
    }

    try {
      final tracks = _localStream!.getAudioTracks();

      if (tracks.isEmpty) {
        print('⚠️ No audio tracks to unmute');
        return;
      }

      for (var track in tracks) {
        track.enabled = true;
        print('🔊 Track ${track.label} enabled');
      }

      _isMicMuted = false;
      print('🔊 Microphone unmuted');
    } catch (e) {
      print('❌ Error unmuting: $e');
    }
  }

  /// Toggle mute
  Future<void> toggleMute() async {
    if (_isMicMuted) {
      await unmuteAudio();
    } else {
      await muteAudio();
    }
  }

  /// Set speaker on/off
  Future<void> setSpeakerphoneOn(bool on) async {
    try {
      _isSpeakerOn = on;
      print(on ? '🔊 Speaker ON' : '🔇 Speaker OFF');

      // Platform-specific speaker control would go here
      // For now, this is a state tracker
    } catch (e) {
      print('❌ Error setting speaker: $e');
    }
  }

  /// Check if audio is working
  Future<bool> testAudio() async {
    try {
      print('🧪 Testing audio...');

      if (!_isInitialized) {
        print('⚠️ Audio not initialized');
        return false;
      }

      if (_localStream == null) {
        print('❌ No local stream');
        return false;
      }

      final tracks = _localStream!.getAudioTracks();

      if (tracks.isEmpty) {
        print('❌ No audio tracks');
        return false;
      }

      print('✅ Audio test passed');
      print('📊 Tracks: ${tracks.length}');

      for (var track in tracks) {
        print('  - ${track.label}: enabled=${track.enabled}');
      }

      return true;
    } catch (e) {
      print('❌ Audio test failed: $e');
      return false;
    }
  }

  /// Get audio statistics
  Map<String, dynamic> getAudioStats() {
    return {
      'isInitialized': _isInitialized,
      'isMicMuted': _isMicMuted,
      'isSpeakerOn': _isSpeakerOn,
      'hasLocalStream': _localStream != null,
      'audioTracksCount': _localStream?.getAudioTracks().length ?? 0,
      'audioTracks': _localStream?.getAudioTracks().map((track) => {
        'label': track.label,
        'enabled': track.enabled,
        'kind': track.kind,
      }).toList() ?? [],
    };
  }

  /// Print current audio status
  void printStatus() {
    print('📊 Audio Service Status:');
    print('  - Initialized: $_isInitialized');
    print('  - Mic Muted: $_isMicMuted');
    print('  - Speaker On: $_isSpeakerOn');
    print('  - Has Stream: ${_localStream != null}');
    print('  - Tracks: ${_localStream?.getAudioTracks().length ?? 0}');
  }

  // Getters
  bool get isMicMuted => _isMicMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isInitialized => _isInitialized;
  MediaStream? get localStream => _localStream;

  /// Dispose and cleanup
  Future<void> dispose() async {
    try {
      print('🧹 Disposing audio service...');

      if (_localStream != null) {
        // Stop all tracks
        for (var track in _localStream!.getTracks()) {
          await track.stop();
          print('⏹️ Stopped track: ${track.label}');
        }

        // Dispose stream
        await _localStream!.dispose();
        _localStream = null;
      }

      _isInitialized = false;
      _isMicMuted = false;

      print('✅ Audio service disposed');
    } catch (e) {
      print('❌ Error disposing: $e');
    }
  }
}
