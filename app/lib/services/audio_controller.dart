import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

class AudioController {
  static final AudioController _instance = AudioController._();
  static AudioController get instance => _instance;
  AudioController._();

  AudioSession? _session;
  bool _micEnabled = false;

  Future<void> initialize() async {
    _session = await AudioSession.instance;
    await _session!.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ),
    );
  }

  Future<void> setMicEnabled(bool enabled) async {
    if (_micEnabled == enabled) return;
    _micEnabled = enabled;
    _session ??= await AudioSession.instance;

    try {
      if (enabled) {
        await _session!.setActive(true);
        await _session!.configure(
          const AudioSessionConfiguration(
            avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
            avAudioSessionCategoryOptions:
                AVAudioSessionCategoryOptions.defaultToSpeaker |
                AVAudioSessionCategoryOptions.allowBluetooth,
            avAudioSessionMode: AVAudioSessionMode.voiceChat,
            androidAudioAttributes: AndroidAudioAttributes(
              contentType: AndroidAudioContentType.speech,
              usage: AndroidAudioUsage.voiceCommunication,
            ),
            androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          ),
        );
      } else {
        await _session!.configure(
          const AudioSessionConfiguration(
            avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
            avAudioSessionCategoryOptions:
                AVAudioSessionCategoryOptions.allowBluetooth,
            avAudioSessionMode: AVAudioSessionMode.voiceChat,
            androidAudioAttributes: AndroidAudioAttributes(
              contentType: AndroidAudioContentType.speech,
              usage: AndroidAudioUsage.voiceCommunication,
            ),
            androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          ),
        );
      }
    } catch (e) {
      debugPrint('AudioController error: $e');
    }
  }

  Future<void> deactivate() async {
    _micEnabled = false;
    await _session?.setActive(false);
  }
}
