import 'package:audioplayers/audioplayers.dart';

/// Sound for بلينكو.
///
/// Peg ticks fire up to sixteen times per drop and several drops overlap during
/// auto-bet, so a single player would cut itself off constantly. A small
/// round-robin pool lets ticks overlap; landings get their own player so a win
/// chime is never clipped by the next ball's first bounce.
class PlinkoSfx {
  PlinkoSfx({this.enabled = true});

  bool enabled;

  static const _pegAssets = [
    'sounds/plinko_peg_1.wav',
    'sounds/plinko_peg_2.wav',
    'sounds/plinko_peg_3.wav',
  ];

  final List<AudioPlayer> _pegPool = List.generate(
      6, (_) => AudioPlayer()..setPlayerMode(PlayerMode.lowLatency));
  final AudioPlayer _landing = AudioPlayer()
    ..setPlayerMode(PlayerMode.lowLatency);
  final AudioPlayer _ui = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);

  int _next = 0;

  Future<void> _fire(AudioPlayer player, String asset, double volume) async {
    if (!enabled) return;
    try {
      await player.stop();
      await player.play(AssetSource(asset), volume: volume);
    } catch (_) {
      // Audio is decoration — never let a playback failure interrupt a drop.
    }
  }

  /// [row] picks the pitch so a descent audibly falls.
  void peg(int row, int totalRows) {
    if (!enabled) return;
    final tier = totalRows <= 1 ? 0 : (row * _pegAssets.length) ~/ totalRows;
    final asset = _pegAssets[tier.clamp(0, _pegAssets.length - 1)];
    final player = _pegPool[_next];
    _next = (_next + 1) % _pegPool.length;
    // Quiet: this is the most-repeated sound in the game.
    _fire(player, asset, 0.22);
  }

  void drop() => _fire(_ui, 'sounds/plinko_drop.wav', 0.35);

  void click() => _fire(_ui, 'sounds/plinko_click.wav', 0.4);

  void landed(double multiplier) {
    if (multiplier >= 10) {
      _fire(_landing, 'sounds/plinko_land_big.wav', 0.85);
    } else if (multiplier >= 1) {
      _fire(_landing, 'sounds/plinko_land_win.wav', 0.6);
    } else {
      _fire(_landing, 'sounds/plinko_land_low.wav', 0.45);
    }
  }

  void dispose() {
    for (final p in _pegPool) {
      p.dispose();
    }
    _landing.dispose();
    _ui.dispose();
  }
}
