import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import '../../services/audio_route.dart';

/// Sound and haptics for عجلة السيارات. Cues come from
/// assets/sounds/generate_car_wheel_sounds.py (original, no licence). Every call
/// is decoration: failures are swallowed, players are made on first use.
class CarWheelSfx {
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
      if (_pool.length < 4) _pool.add(_make());
      final player = _pool[_next++ % _pool.length];
      await player.stop();
      if (_disposed) return;
      await player.play(
        AssetSource('sounds/car_wheel_$name.wav'),
        volume: volume * AudioRoute.instance.masterVolume,
      );
    } catch (_) {}
  }

  void _haptic(Future<void> Function() feedback) {
    if (!enabled || _disposed) return;
    feedback().catchError((Object _) {});
  }

  void click() => _fire('click', .5);
  void chip() {
    _fire('chip', .6);
    _haptic(HapticFeedback.selectionClick);
  }

  void clear() => _fire('clear', .6);
  void lock() => _fire('lock', .6);
  void spin() => _fire('spin', .45);

  /// The ball crossing a pocket divider; restarted, never stacked.
  Future<void> tick() async {
    if (!enabled || _disposed) return;
    try {
      final player = _tick ??= _make()..setReleaseMode(ReleaseMode.stop);
      await player.stop();
      await player.play(
        AssetSource('sounds/car_wheel_tick.wav'),
        volume: .3 * AudioRoute.instance.masterVolume,
      );
    } catch (_) {}
  }

  void stop() {
    _fire('stop', .7);
    _haptic(HapticFeedback.mediumImpact);
  }

  void win(bool big) {
    _fire(big ? 'big_win' : 'win', .7);
    _haptic(HapticFeedback.heavyImpact);
  }

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
