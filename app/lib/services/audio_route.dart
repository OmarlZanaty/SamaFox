import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' show Hardware;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/permission_gate.dart';

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

  /// A3 — the room's volume slider, applied to every registered player.
  ///
  /// The slider used to reach the room's voice, the effects player and the
  /// seat clip, and nothing else: a user who dragged it to zero to quiet the
  /// room still had a game firing cues at full volume over it. Games register
  /// their players here already, so this is the one place that can hold the
  /// choice for all of them.
  double masterVolume = 1.0;

  /// True while a voice engine holds a call (mesh or LiveKit).
  ///
  /// `audioplayers` writes the phone's GLOBAL audio mode on every
  /// `setAudioContext`, not just the player's. With the loudspeaker chosen that
  /// was `MODE_NORMAL` — and the room registers its own player on entry, so
  /// every room session knocked WebRTC out of `MODE_IN_COMMUNICATION`, where
  /// Android's hardware echo canceller lives. Four or five open mics on
  /// loudspeaker then fed each other back ("تردد صوت"). During a call the mode
  /// stays in-communication; the speaker flag alone picks the output.
  bool _voiceLive = false;

  /// Called by the voice engines when a call starts and ends.
  Future<void> setVoiceLive(bool live) async {
    if (_voiceLive == live) return;
    _voiceLive = live;
    await apply();
  }

  static const String _speakerKey = 'audio_route_speaker_on';
  static const String _volumeKey = 'audio_route_master_volume';

  /// Load the user's saved choices. Safe to call more than once.
  ///
  /// A3 — neither of these survived a restart: the user set the earpiece, came
  /// back, and was on loudspeaker again with no indication why.
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // SPEC52 #3 — routing is automatic now (headset if one is connected,
      // loudspeaker otherwise), so an old "earpiece" choice is not restored.
      speakerOn = true;
      masterVolume = (prefs.getDouble(_volumeKey) ?? masterVolume).clamp(0.0, 1.0);
    } catch (e) {
      // A preferences failure must not cost anyone their audio; the defaults
      // are the same ones that shipped before this was persisted.
      debugPrint('[AudioRoute] restore failed: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_speakerKey, speakerOn);
      await prefs.setDouble(_volumeKey, masterVolume);
    } catch (e) {
      debugPrint('[AudioRoute] persist failed: $e');
    }
  }

  // ── SPEC52 #3: automatic audio routing ────────────────────────────────────
  //
  // No speaker button any more. A wired headset or a Bluetooth headset/earbuds
  // takes BOTH the sound and the microphone as soon as it is connected (Android
  // AudioSwitch: Bluetooth HFP/SCO first, then wired); when it goes away the
  // phone's loudspeaker and microphone come back. An output-only (A2DP)
  // Bluetooth device has no call microphone, so the phone mic stays and the
  // system picks the best output. Nothing here touches the room connection or
  // the published track — a route change never drops anyone from the room.

  StreamSubscription<dynamic>? _deviceSub;
  Timer? _routeDebounce;
  bool _btAsked = false;

  /// Apply the automatic route now and keep following device changes.
  Future<void> applyAutomatic() async {
    _watchDevices();
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        await rtc.Helper.setSpeakerphoneOnButPreferBluetooth();
      } else if (Platform.isIOS) {
        // iOS already prefers a connected headset over the speaker.
        await rtc.Helper.setSpeakerphoneOn(true);
      }
    } catch (e) {
      debugPrint('[AudioRoute] automatic route failed: $e');
    }
  }

  void _watchDevices() {
    if (_deviceSub != null) return;
    try {
      _deviceSub = Hardware.instance.onDeviceChange.stream.listen((_) {
        _routeDebounce?.cancel();
        // A headset connecting fires several changes in a row; settle first.
        _routeDebounce = Timer(const Duration(milliseconds: 400), () {
          unawaited(applyAutomatic());
        });
      });
    } catch (e) {
      debugPrint('[AudioRoute] device watch failed: $e');
    }
  }

  /// Android 12+ needs BLUETOOTH_CONNECT to see a Bluetooth headset at all.
  /// Asked once per app run, never blocks entering the room.
  Future<void> ensureBluetoothPermission() async {
    if (_btAsked || kIsWeb || !Platform.isAndroid) return;
    _btAsked = true;
    try {
      final st = await PermissionGate.request(Permission.bluetoothConnect)
          .timeout(const Duration(seconds: 20));
      if (st.isGranted) await applyAutomatic();
    } catch (e) {
      debugPrint('[AudioRoute] bluetooth permission: $e');
    }
  }

  /// Flip the route and remember it.
  Future<void> setSpeaker(bool on) async {
    speakerOn = on;
    await apply();
    await _persist();
  }

  /// Set the level every registered player uses, and remember it.
  Future<void> setMasterVolume(double v) async {
    masterVolume = v.clamp(0.0, 1.0);
    await applyVolume();
    await _persist();
  }

  /// SPEC52 #18 — "كتم صوت الغرفة": silences everything the ROOM plays for
  /// this user only (voice, music, gift/entrance sounds). The user's own
  /// microphone is untouched. Renderers read it when they start a sound, and
  /// listen to it to react mid-play.
  final ValueNotifier<bool> roomMuted = ValueNotifier<bool>(false);

  /// What players should use right now: 0 while the room is muted.
  double get effectiveVolume => roomMuted.value ? 0.0 : masterVolume;

  Future<void> setRoomMuted(bool muted) async {
    roomMuted.value = muted;
    await applyVolume();
  }

  /// Push [masterVolume] to every registered player.
  Future<void> applyVolume() async {
    // Iterate a snapshot: each await yields, and a screen closing meanwhile
    // unregisters its players — iterating the live set threw "Concurrent
    // modification during iteration" on room leave (1.0.46 crash reports).
    for (final p in List.of(_players)) {
      if (!_players.contains(p)) continue;
      try {
        await p.setVolume(effectiveVolume);
      } catch (e) {
        debugPrint('[AudioRoute] volume failed: $e');
      }
    }
  }

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
          // During a call it must stay `inCommunication` whatever the route —
          // see [_voiceLive].
          audioMode: speaker && !_voiceLive
              ? AndroidAudioMode.normal
              : AndroidAudioMode.inCommunication,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType:
              speaker ? AndroidUsageType.media : AndroidUsageType.voiceCommunication,
          // `none` so a game cue never ducks or stops the room's voice.
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(
          // The session is shared with WebRTC: `playback` mid-call would drop
          // the microphone and its voice processing.
          category: speaker && !_voiceLive
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
    try {
      // Before the route, and regardless of platform: a game opened while the
      // room is muted must not play its first cue at full volume.
      await player.setVolume(masterVolume);
    } catch (e) {
      debugPrint('[AudioRoute] initial volume failed: $e');
    }
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
    for (final p in List.of(players)) {
      await register(p);
    }
  }

  void unregisterAll(Iterable<AudioPlayer> players) =>
      List.of(players).forEach(unregister);

  /// Re-apply the current route to every registered player. Called by the room
  /// when the user flips the icon.
  Future<void> apply() async {
    if (!_supported) return;
    final ctx = _contextFor(speakerOn);
    // Snapshot for the same reason as [applyVolume].
    for (final p in List.of(_players)) {
      if (!_players.contains(p)) continue;
      try {
        await p.setAudioContext(ctx);
      } catch (e) {
        debugPrint('[AudioRoute] apply failed: $e');
      }
    }
  }
}
