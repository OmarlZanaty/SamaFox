import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import '../../services/audio_route.dart';

/// Sound and haptics for FRUIT WHEEL.
///
/// Cues come from assets/sounds/generate_fruit_wheel_sounds.py (original, no
/// licence). Every call is decoration: failures are swallowed, and players are
/// created on first use so muted sessions and tests never touch the platform.
class FruitWheelSfx {
  bool enabled = true;
  bool _disposed = false;
  final List<AudioPlayer> _pool = [];
  int _next = 0;
  AudioPlayer? _tick;

  AudioPlayer _make() {
    final player = AudioPlayer();
    AudioRoute.instance.register(player);
    return player;
  }

  Future<void> _fire(String name, double volume) async {
    if (!enabled || _disposed) return;
    try {
      if (_pool.length < 3) _pool.add(_make());
      final player = _pool[_next++ % _pool.length];
      await player.stop();
      if (_disposed) return;
      await player.play(
        AssetSource('sounds/fruitwheel_$name.wav'),
        volume: volume * AudioRoute.instance.masterVolume,
      );
    } catch (_) {}
  }

  void _haptic(Future<void> Function() feedback) {
    if (!enabled || _disposed) return;
    feedback().catchError((Object _) {});
  }

  void click() {
    _fire('click', .5);
    _haptic(HapticFeedback.selectionClick);
  }

  void spin() => _fire('spin', .45);

  /// The pointer passing a segment border. Its own player, so ticks never
  /// cut off the other cues; a tick still playing is simply restarted.
  Future<void> tick() async {
    if (!enabled || _disposed) return;
    try {
      final player = _tick ??= _make()..setReleaseMode(ReleaseMode.stop);
      await player.stop();
      await player.play(
        AssetSource('sounds/fruitwheel_tick.wav'),
        volume: .35 * AudioRoute.instance.masterVolume,
      );
    } catch (_) {}
  }

  void stop() {
    _fire('stop', .6);
    _haptic(HapticFeedback.mediumImpact);
  }

  void win(bool big) {
    _fire(big ? 'big_win' : 'win', .7);
    _haptic(HapticFeedback.heavyImpact);
  }

  void bonus() => _fire('bonus', .7);
  void orb() => _fire('orb', .7);

  void dispose() {
    _disposed = true;
    for (final p in [..._pool, if (_tick != null) _tick!]) {
      try {
        p.dispose();
      } catch (_) {}
    }
    _pool.clear();
  }
}
