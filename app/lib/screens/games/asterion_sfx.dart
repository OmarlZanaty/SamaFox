import 'package:audioplayers/audioplayers.dart';

import '../../services/audio_route.dart';

/// Sound for أستيريون. Every cue is decoration — a missing file or a playback
/// failure must never interrupt a spin, same contract as PlinkoSfx.
///
/// The cues are laid out so intensity can climb with the cascade: [tumble] takes
/// a step index and rises in pitch through a small pool of players, so a four-
/// step cascade is audibly bigger than a one-step one without new assets.
class AsterionSfx {
  AsterionSfx({this.enabled = true, double volume = 1.0}) : _volume = volume {
    // A3 / G3(e) — game sound must follow the room's سماعة toggle. These
    // players are created here and shared with nothing, so registering them
    // is the only way a route change can ever reach them.
    AudioRoute.instance.registerAll(_routedPlayers);
  }

  /// Every player this class owns, for audio-route registration.
  List<AudioPlayer> get _routedPlayers => [_ui, _board, _feature, ..._pool];

  bool enabled;
  double _volume;

  /// Master level, 0..1. Each cue keeps its own mix balance and is scaled by
  /// this, so a quieter setting does not flatten the sound design.
  double get volume => _volume;
  set volume(double v) => _volume = v.clamp(0.0, 1.0);

  final AudioPlayer _ui = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
  final AudioPlayer _board = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
  final AudioPlayer _feature = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
  final List<AudioPlayer> _pool =
      List.generate(3, (_) => AudioPlayer()..setPlayerMode(PlayerMode.lowLatency));
  int _next = 0;

  Future<void> _fire(AudioPlayer player, String asset, double volume, {double rate = 1.0}) async {
    if (!enabled) return;
    try {
      await player.stop();
      await player.setPlaybackRate(rate);
      await player.play(AssetSource(asset), volume: volume * _volume);
    } catch (_) {
      // Audio is decoration only.
    }
  }

  void spin() => _fire(_ui, 'sounds/asterion_spin.wav', 0.5);
  void deal() => _fire(_board, 'sounds/asterion_deal.wav', 0.35);

  /// [step] is the cascade depth, 0-based; each step lifts the pitch a little.
  void tumble(int step) {
    final p = _pool[_next];
    _next = (_next + 1) % _pool.length;
    _fire(p, 'sounds/asterion_tumble.wav', 0.5, rate: (1.0 + step * 0.06).clamp(1.0, 1.5));
  }

  void burst() => _fire(_board, 'sounds/asterion_burst.wav', 0.4);
  void refill() => _fire(_board, 'sounds/asterion_refill.wav', 0.3);
  void orbLand() => _fire(_feature, 'sounds/asterion_orb_land.wav', 0.5);
  void orbCollect() => _fire(_feature, 'sounds/asterion_orb_collect.wav', 0.6);
  void crest() => _fire(_feature, 'sounds/asterion_crest.wav', 0.55);
  void trialStart() => _fire(_feature, 'sounds/asterion_trial.wav', 0.7);
  void trialEnd() => _fire(_ui, 'sounds/asterion_trial_end.wav', 0.6);

  void celebration(String tier) {
    final asset = switch (tier) {
      'DIVINE_SURGE' => 'sounds/asterion_celebrate_top.wav',
      'EPIC_STORM' => 'sounds/asterion_celebrate_high.wav',
      'GREAT_SURGE' => 'sounds/asterion_celebrate_mid.wav',
      _ => 'sounds/asterion_celebrate_low.wav',
    };
    _fire(_feature, asset, 0.8);
  }

  void click() => _fire(_ui, 'sounds/asterion_click.wav', 0.4);
  void error() => _fire(_ui, 'sounds/asterion_error.wav', 0.4);

  void dispose() {
    AudioRoute.instance.unregisterAll(_routedPlayers);
    _ui.dispose();
    _board.dispose();
    _feature.dispose();
    for (final p in _pool) {
      p.dispose();
    }
  }
}
