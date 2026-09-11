import 'package:audioplayers/audioplayers.dart';

import '../../services/audio_route.dart';

/// Sound for بوابات أوليمبوس.
///
/// Every cue is decoration — a missing file or a playback failure must never
/// interrupt a spin, the same contract as PlinkoSfx and AetherfallSfx. The
/// assets are synthesised by assets/sounds/generate_olympus_sounds.py, so they
/// are original and carry no licence.
class OlympusSfx {
  OlympusSfx({this.enabled = true, double volume = 1.0}) : _volume = volume {
    // A3 / G3(e) — game sound must follow the room's سماعة toggle. These
    // players are owned here and shared with nothing, so registering them is
    // the only way a route change can reach them.
    AudioRoute.instance.registerAll(_routedPlayers);
  }

  List<AudioPlayer> get _routedPlayers => [_ui, _board, _feature, ..._tumblePool];

  bool enabled;

  double _volume;

  /// Master level, 0..1. Each cue keeps its own mix balance and is scaled by
  /// this, so turning the game down does not flatten the sound design.
  double get volume => _volume;
  set volume(double v) => _volume = v.clamp(0.0, 1.0);

  final AudioPlayer _ui = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
  final AudioPlayer _board = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
  final AudioPlayer _feature = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);

  /// A cascade fires several win cues close together, so they round-robin
  /// across a small pool rather than cutting each other off.
  final List<AudioPlayer> _tumblePool =
      List.generate(3, (_) => AudioPlayer()..setPlayerMode(PlayerMode.lowLatency));
  int _next = 0;

  Future<void> _fire(AudioPlayer player, String asset, double volume) async {
    if (!enabled) return;
    try {
      await player.stop();
      await player.play(AssetSource(asset), volume: volume * _volume);
    } catch (_) {
      // Audio is decoration only.
    }
  }

  void spin() => _fire(_ui, 'sounds/olympus_spin.wav', 0.5);
  void deal() => _fire(_board, 'sounds/olympus_deal.wav', 0.4);

  void win() {
    final p = _tumblePool[_next];
    _next = (_next + 1) % _tumblePool.length;
    _fire(p, 'sounds/olympus_win.wav', 0.5);
  }

  void burst() => _fire(_board, 'sounds/olympus_burst.wav', 0.42);
  void tumble() => _fire(_board, 'sounds/olympus_tumble.wav', 0.34);
  void orbLanding() => _fire(_feature, 'sounds/olympus_orb.wav', 0.45);
  void strike() => _fire(_feature, 'sounds/olympus_strike.wav', 0.75);
  void collect() => _fire(_feature, 'sounds/olympus_collect.wav', 0.55);
  void scatter() => _fire(_feature, 'sounds/olympus_scatter.wav', 0.6);
  void bonusTransition() => _fire(_feature, 'sounds/olympus_bonus_transition.wav', 0.75);
  void bonusSummary() => _fire(_ui, 'sounds/olympus_bonus_summary.wav', 0.6);
  void retrigger() => _fire(_feature, 'sounds/olympus_retrigger.wav', 0.55);

  void celebration(String tier) {
    final asset = switch (tier) {
      'EPIC_WIN' => 'sounds/olympus_celebrate_top.wav',
      'MEGA_WIN' => 'sounds/olympus_celebrate_high.wav',
      'BIG_WIN' => 'sounds/olympus_celebrate_mid.wav',
      _ => 'sounds/olympus_celebrate_low.wav',
    };
    _fire(_feature, asset, 0.8);
  }

  void click() => _fire(_ui, 'sounds/olympus_click.wav', 0.4);
  void error() => _fire(_ui, 'sounds/olympus_error.wav', 0.45);

  void dispose() {
    AudioRoute.instance.unregisterAll(_routedPlayers);
    _ui.dispose();
    _board.dispose();
    _feature.dispose();
    for (final p in _tumblePool) {
      p.dispose();
    }
  }
}
