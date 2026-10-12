import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import '../../services/audio_route.dart';

/// Sound and haptics for YUMMY.
///
/// Cues come from assets/sounds/generate_yummy_sounds.py (original, no
/// licence). Every call is decoration: a missing file, a busy player or a
/// disposed screen must never interrupt a round, so failures are swallowed.
/// Players are created on first use, which keeps tests and muted sessions
/// free of platform channels.
class YummySfx {
  bool enabled = true;
  bool haptics = true;
  bool _disposed = false;

  /// Spin loop, then the free-spins music: one looping player.
  AudioPlayer? _loop;

  /// One-shots round-robin over a small pool so a tumble's pops and its win
  /// jingle overlap instead of cutting each other off.
  final List<AudioPlayer> _pool = [];
  int _next = 0;
  String? _looping;

  List<AudioPlayer> get _players => [if (_loop != null) _loop!, ..._pool];

  AudioPlayer _make() {
    final player = AudioPlayer();
    AudioRoute.instance.register(player);
    return player;
  }

  Future<void> _fire(String name, double volume) async {
    if (!enabled || _disposed) return;
    try {
      if (_pool.length < 4) _pool.add(_make());
      final player = _pool[_next % _pool.length];
      _next++;
      await player.stop();
      if (_disposed) return;
      await player.play(
        AssetSource('sounds/yummy_$name.wav'),
        volume: volume * AudioRoute.instance.masterVolume,
      );
    } catch (_) {}
  }

  Future<void> _startLoop(String name, double volume) async {
    if (!enabled || _disposed || _looping == name) return;
    _looping = name;
    try {
      final player = _loop ??= _make();
      await player.stop();
      await player.setReleaseMode(ReleaseMode.loop);
      if (_disposed || _looping != name) return;
      await player.play(
        AssetSource('sounds/yummy_$name.wav'),
        volume: volume * AudioRoute.instance.masterVolume,
      );
    } catch (_) {}
  }

  Future<void> stopLoop([String? name]) async {
    if (name != null && _looping != name) return;
    _looping = null;
    try {
      await _loop?.stop();
    } catch (_) {}
  }

  void _haptic(Future<void> Function() feedback) {
    if (!haptics || _disposed) return;
    feedback().catchError((Object _) {});
  }

  void spinStart() => _startLoop('spin_loop', .35);
  void spinEnd() => stopLoop('spin_loop');
  void reelStop(int reel) {
    _fire('reel_stop', .5);
    _haptic(HapticFeedback.selectionClick);
  }

  void bonusLand() => _fire('bonus_land', .6);
  void anticipation() => _fire('anticipation', .5);
  void tumblePop() => _fire('tumble_pop', .5);
  void win() {
    _fire('win_small', .55);
    _haptic(HapticFeedback.lightImpact);
  }

  void bigWin() {
    _fire('win_big', .75);
    _fire('coins', .5);
    _haptic(HapticFeedback.heavyImpact);
  }

  void coins() => _fire('coins', .45);
  void expand() {
    _fire('expand', .6);
    _haptic(HapticFeedback.mediumImpact);
  }

  void freeSpinsIntro() {
    _fire('fs_intro', .7);
    _haptic(HapticFeedback.heavyImpact);
  }

  void freeSpinsMusic() => _startLoop('fs_music', .4);
  void freeSpinsEnd() => stopLoop('fs_music');
  void click() => _fire('click', .4);

  // Kept for callers that predate the v2 cues.
  void spin() => spinStart();
  void jackpot() => bigWin();

  void set(bool on) {
    enabled = on;
    if (!on) stopLoop();
  }

  void dispose() {
    _disposed = true;
    final players = _players;
    _pool.clear();
    _loop = null;
    AudioRoute.instance.unregisterAll(players);
    for (final player in players) {
      // Stop first: disposing a playing Android player can leak its decoder.
      player
          .stop()
          .catchError((Object _) {})
          .whenComplete(() => player.dispose().catchError((Object _) {}));
    }
  }
}
