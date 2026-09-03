import 'package:audioplayers/audioplayers.dart';

/// Sound for القط الجشع.
///
/// The assets are generated, not sourced — see
/// app/assets/sounds/generate_greedy_sounds.py.
///
/// Two independent switches, because they fail differently: [musicEnabled]
/// controls the looping spin bed, [sfxEnabled] the one-shots. Segment ticks
/// fire eight times a second at the top of a spin, so they get a small
/// round-robin pool; a win chime must never be clipped by the next tick, so it
/// gets a player of its own.
class GreedyCatSfx {
  GreedyCatSfx({this.sfxEnabled = true, this.musicEnabled = true});

  bool sfxEnabled;
  bool musicEnabled;

  final List<AudioPlayer> _tickPool = List.generate(
      4, (_) => AudioPlayer()..setPlayerMode(PlayerMode.lowLatency));
  final AudioPlayer _ui = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
  final AudioPlayer _result = AudioPlayer()..setPlayerMode(PlayerMode.lowLatency);
  final AudioPlayer _spin = AudioPlayer()..setPlayerMode(PlayerMode.mediaPlayer);
  final AudioPlayer _music = AudioPlayer()
    ..setPlayerMode(PlayerMode.mediaPlayer)
    ..setReleaseMode(ReleaseMode.loop);

  int _next = 0;

  Future<void> _fire(AudioPlayer player, String asset, double volume) async {
    if (!sfxEnabled) return;
    try {
      await player.stop();
      await player.play(AssetSource(asset), volume: volume);
    } catch (_) {
      // Audio is decoration — never let a playback failure interrupt a round.
    }
  }

  /// Denomination tile, category button, tab.
  void click() => _fire(_ui, 'sounds/greedy_click.wav', 0.4);

  /// A coin landing on a food card.
  void coin() => _fire(_ui, 'sounds/greedy_coin.wav', 0.5);

  /// One of the last five seconds of the selection window.
  void countdown() => _fire(_ui, 'sounds/greedy_tick.wav', 0.35);

  /// The highlight sweeping past one food card during the spin. Deliberately
  /// the quietest sound in the game — it is also the most repeated.
  void segment() {
    if (!sfxEnabled) return;
    final player = _tickPool[_next];
    _next = (_next + 1) % _tickPool.length;
    _fire(player, 'sounds/greedy_segment.wav', 0.16);
  }

  /// The looping carnival bed, started when the screen opens and left running
  /// for the session. Synthesised, not sourced — see the generator script.
  Future<void> startMusic() async {
    if (!musicEnabled) return;
    try {
      // Quiet on purpose: it sits under a countdown tick and a spin ratchet.
      await _music.play(AssetSource('sounds/greedy_theme.wav'), volume: 0.22);
    } catch (_) {
      // Blocked autoplay or a missing decoder is not worth interrupting a
      // round over — the game is entirely playable in silence.
    }
  }

  Future<void> stopMusic() async {
    try {
      await _music.stop();
    } catch (_) {}
  }

  /// The wheel spin bed. Follows the music switch, not the effects switch,
  /// because it is the one continuous sound in the game.
  Future<void> spin() async {
    if (!musicEnabled) return;
    try {
      await _spin.stop();
      await _spin.play(AssetSource('sounds/greedy_spin.wav'), volume: 0.45);
    } catch (_) {
      // Same as above — a silent spin is better than a broken one.
    }
  }

  Future<void> stopSpin() async {
    try {
      await _spin.stop();
    } catch (_) {}
  }

  /// The wheel has stopped, before win or loss is known.
  void stopped() => _fire(_result, 'sounds/greedy_result.wav', 0.55);

  void win() => _fire(_result, 'sounds/greedy_win.wav', 0.8);

  void lose() => _fire(_result, 'sounds/greedy_lose.wav', 0.4);

  void milestone() => _fire(_result, 'sounds/greedy_milestone.wav', 0.7);

  /// Used once per winning result at most, so the cat never becomes a nag.
  void meow() => _fire(_ui, 'sounds/greedy_meow.wav', 0.45);

  void modalOpen() => _fire(_ui, 'sounds/greedy_modal_open.wav', 0.35);

  void modalClose() => _fire(_ui, 'sounds/greedy_modal_close.wav', 0.3);

  void dispose() {
    for (final p in _tickPool) {
      p.dispose();
    }
    _ui.dispose();
    _result.dispose();
    _spin.dispose();
    _music.dispose();
  }
}
