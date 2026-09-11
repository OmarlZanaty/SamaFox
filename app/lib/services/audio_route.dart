import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// A3 / G3(e) — the single source of truth for "speaker or earpiece".
///
/// The client's report: *"ايقونة السماعه موجوده لكن غير فعاله"*, and when the
/// speaker is on **everything** must come out of it — the room and the games
/// both ("صوت الغرفه وصوت الالعاب، لعبة الصاروخ تحديدا").
///
/// It was ineffective for two separate reasons:
///
///  1. `WebRTCAudioService._applyEchoSafeMode` ignored its own `talking`
///     argument and forced the loudspeaker on unconditionally. It runs on mute,
///     on unmute, on init and every time the mic is re-acquired, so whatever
///     the user picked was overwritten within seconds.
///  2. Game sound effects are `audioplayers` instances created independently
///     inside each game screen. They never shared any routing state with the
///     voice engine at all, so the room could be on the earpiece while the
///     rocket game played out loud.
///
/// This holds the choice in one place. The WebRTC service reads it instead of
/// hard-coding `true`, and every game SFX pool registers its players here so a
/// single toggle moves all of them.
class AudioRoute {
  AudioRoute._();
  static final AudioRoute instance = AudioRoute._();

  /// The user's choice. Loudspeaker by default — a voice room nobody can hear
  /// across the room is the worse failure of the two.
  ///
  /// Written when the user flips the in-room speaker icon; anything that later
  /// re-applies a route reads this rather than assuming.
  bool speakerOn = true;

  /// Players whose route must follow the toggle. Held weakly by convention:
  /// a game screen calls [unregister] in its dispose.
  final Set<AudioPlayer> _players = <AudioPlayer>{};

  bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// The `AudioContext` matching the current choice.
  ///
  /// `AndroidUsageType.voiceCommunication` on the earpiece is what actually
  /// moves a game sound off the loudspeaker; leaving it as `media` would keep
  /// it on the speaker no matter what the voice engine is doing.
  AudioContext _contextFor(bool speaker) => AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: speaker,
          // `inCommunication` is what actually lets Android hand a stream to
          // the earpiece. Left on the default `normal`, a sound keeps coming
          // out of the loudspeaker however the usage type is labelled.
          audioMode: speaker ? AndroidAudioMode.normal : AndroidAudioMode.inCommunication,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType:
              speaker ? AndroidUsageType.media : AndroidUsageType.voiceCommunication,
          // `none` so a game cue never ducks or stops the room's voice.
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(
          category: speaker
              ? AVAudioSessionCategory.playback
              : AVAudioSessionCategory.playAndRecord,
          options: [
            // Never interrupt the WebRTC session this app is built around.
            AVAudioSessionOptions.mixWithOthers,
            if (speaker) AVAudioSessionOptions.defaultToSpeaker,
          ],
        ),
      );

  /// Register a game's player so it follows the toggle. Applies the current
  /// route immediately, so a screen opened while the earpiece is selected does
  /// not blast its first sound out of the speaker.
  Future<void> register(AudioPlayer player) async {
    _players.add(player);
    if (!_supported) return;
    try {
      await player.setAudioContext(_contextFor(speakerOn));
    } catch (e) {
      // Sound is decoration — never let a routing failure break a game.
      debugPrint('[AudioRoute] register failed: $e');
    }
  }

  void unregister(AudioPlayer player) => _players.remove(player);

  /// Convenience for the game SFX pools, which each own a handful of players.
  Future<void> registerAll(Iterable<AudioPlayer> players) async {
    for (final p in players) {
      await register(p);
    }
  }

  void unregisterAll(Iterable<AudioPlayer> players) => players.forEach(unregister);

  /// Re-apply the current route to every registered player. Called by the room
  /// when the user flips the icon.
  Future<void> apply() async {
    if (!_supported) return;
    final ctx = _contextFor(speakerOn);
    for (final p in _players) {
      try {
        await p.setAudioContext(ctx);
      } catch (e) {
        debugPrint('[AudioRoute] apply failed: $e');
      }
    }
  }
}
