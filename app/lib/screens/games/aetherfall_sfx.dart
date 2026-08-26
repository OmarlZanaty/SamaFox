import 'package:audioplayers/audioplayers.dart';

/// Sound for أثيرفول. Every cue is decoration — a missing file or a playback
/// failure must never interrupt a spin, same contract as PlinkoSfx.
class AetherfallSfx {
  AetherfallSfx({this.enabled = true});

  bool enabled;

  final AudioPlayer _ui = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
  final AudioPlayer _land = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
  final AudioPlayer _feature = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
  final List<AudioPlayer> _tumblePool =
      List.generate(3, (_) => AudioPlayer()..setPlayerMode(PlayerMode.lowLatency));
  int _next = 0;

  Future<void> _fire(AudioPlayer player, String asset, double volume) async {
    if (!enabled) return;
    try {
      await player.stop();
      await player.play(AssetSource(asset), volume: volume);
    } catch (_) {
      // Audio is decoration only.
    }
  }

  void ignite() => _fire(_ui, 'sounds/aetherfall_ignite.wav', 0.5);
  void chamberPopulate() => _fire(_ui, 'sounds/aetherfall_populate.wav', 0.35);

  void winDiscovery() {
    final p = _tumblePool[_next];
    _next = (_next + 1) % _tumblePool.length;
    _fire(p, 'sounds/aetherfall_win.wav', 0.5);
  }

  void dissolve() => _fire(_land, 'sounds/aetherfall_dissolve.wav', 0.4);
  void refill() => _fire(_land, 'sounds/aetherfall_refill.wav', 0.3);
  void chargeLanding() => _fire(_feature, 'sounds/aetherfall_charge.wav', 0.45);
  void wildActivate() => _fire(_feature, 'sounds/aetherfall_wild.wav', 0.5);
  void keyCollect() => _fire(_feature, 'sounds/aetherfall_key.wav', 0.55);
  void bonusTransition() => _fire(_feature, 'sounds/aetherfall_bonus_transition.wav', 0.7);
  void constellationLock() => _fire(_feature, 'sounds/aetherfall_lock.wav', 0.45);
  void starburst() => _fire(_feature, 'sounds/aetherfall_starburst.wav', 0.65);

  void celebration(String tier) {
    final asset = switch (tier) {
      'AETHERFALL' => 'sounds/aetherfall_celebrate_top.wav',
      'CELESTIAL_BREAK' => 'sounds/aetherfall_celebrate_high.wav',
      'SKYFIRE_SURGE' => 'sounds/aetherfall_celebrate_mid.wav',
      _ => 'sounds/aetherfall_celebrate_low.wav',
    };
    _fire(_feature, asset, 0.8);
  }

  void bonusSummary() => _fire(_ui, 'sounds/aetherfall_bonus_summary.wav', 0.6);
  void mute() => _fire(_ui, 'sounds/aetherfall_click.wav', 0.4);
  void error() => _fire(_ui, 'sounds/aetherfall_error.wav', 0.4);

  void dispose() {
    _ui.dispose();
    _land.dispose();
    _feature.dispose();
    for (final p in _tumblePool) {
      p.dispose();
    }
  }
}
