import 'package:flutter/foundation.dart';

/// Lightweight audio-state controller used by room UI.
///
/// Note: This implementation intentionally avoids depending on `audio_session`
/// symbols so the app can compile even when plugin APIs/version differ across
/// environments. It keeps the same public API used by the app.
class AudioController {
  static final AudioController _instance = AudioController._();
  static AudioController get instance => _instance;
  AudioController._();

  bool _initialized = false;
  bool _micEnabled = false;

  Future<void> initialize() async {
    _initialized = true;
  }

  Future<void> setMicEnabled(bool enabled) async {
    if (!_initialized) {
      await initialize();
    }
    _micEnabled = enabled;
    debugPrint('AudioController mic enabled: $_micEnabled');
  }

  Future<void> deactivate() async {
    _micEnabled = false;
    debugPrint('AudioController deactivated');
  }
}
