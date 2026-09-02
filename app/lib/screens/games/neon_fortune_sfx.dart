import 'package:audioplayers/audioplayers.dart';

/// Sound for نيون فورتشن. Every cue is decoration — a missing file or a playback
/// failure must never interrupt a spin, same contract as PlinkoSfx and
/// AetherfallSfx. No result is ever communicated by sound alone.
class NeonFortuneSfx {
  NeonFortuneSfx({this.enabled = true});

  bool enabled;

  final AudioPlayer _ui = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
  final AudioPlayer _feature = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
  final List<AudioPlayer> _stopPool =
      List.generate(5, (_) => AudioPlayer()..setPlayerMode(PlayerMode.lowLatency));
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

  void spinStart() => _fire(_ui, 'sounds/neon_spin.wav', 0.45);

  void reelStop() {
    final p = _stopPool[_next];
    _next = (_next + 1) % _stopPool.length;
    _fire(p, 'sounds/neon_reel_stop.wav', 0.4);
  }

  void lineWin() => _fire(_ui, 'sounds/neon_line_win.wav', 0.5);
  void betChange() => _fire(_ui, 'sounds/neon_click.wav', 0.35);
  void scatterLand() => _fire(_feature, 'sounds/neon_scatter.wav', 0.55);
  void tokenLand() => _fire(_feature, 'sounds/neon_token.wav', 0.55);
  void freeSpinsStart() => _fire(_feature, 'sounds/neon_rush_start.wav', 0.7);
  void vaultOpen() => _fire(_feature, 'sounds/neon_vault.wav', 0.7);
  void capsule() => _fire(_ui, 'sounds/neon_capsule.wav', 0.45);
  void error() => _fire(_ui, 'sounds/neon_error.wav', 0.4);

  void celebration(String tier) {
    final asset = switch (tier) {
      'CITY_LIGHTS' => 'sounds/neon_celebrate_top.wav',
      'MEGA_WIN' => 'sounds/neon_celebrate_high.wav',
      'BIG_WIN' => 'sounds/neon_celebrate_mid.wav',
      _ => 'sounds/neon_celebrate_low.wav',
    };
    _fire(_feature, asset, 0.8);
  }

  void dispose() {
    _ui.dispose();
    _feature.dispose();
    for (final p in _stopPool) {
      p.dispose();
    }
  }
}
