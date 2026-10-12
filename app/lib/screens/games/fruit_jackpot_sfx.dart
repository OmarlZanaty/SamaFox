import 'package:audioplayers/audioplayers.dart';
import '../../services/audio_route.dart';

class FruitJackpotSfx {
  bool enabled = true;
  AudioPlayer? _player;
  bool _disposed = false;
  Future<void> _play(String asset) async {
    if (!enabled || _disposed) return;
    try {
      if (_player == null) {
        _player = AudioPlayer();
        AudioRoute.instance.registerAll([_player!]);
      }
      await _player!.stop();
      if (!_disposed) await _player!.play(AssetSource(asset), volume: .45);
    } catch (_) {}
  }

  void spin() => _play('sounds/neon_spin.wav');
  void win() => _play('sounds/neon_line_win.wav');
  void jackpot() => _play('sounds/neon_celebrate_top.wav');
  void click() => _play('sounds/neon_click.wav');
  void dispose() {
    _disposed = true;
    final player = _player;
    if (player != null) {
      AudioRoute.instance.unregisterAll([player]);
      () async {
        try {
          await player.stop();
          await player.dispose();
        } catch (_) {}
      }();
    }
  }
}
