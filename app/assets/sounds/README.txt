Drop generated sound files here.

Required file:
  vip_gift.mp3   - plays when a VIP/legendary gift is sent (3-4 seconds)

Played from:
  app/lib/gifts/widgets/gift_animation_overlay.dart  ->  _triggerVip()
    await _vipPlayer.play(AssetSource('sounds/vip_gift.mp3'), volume: 0.9);

Crash game (طيّار) sounds - GENERATED, do not hand-edit. Regenerate with:
    python generate_crash_sounds.py
WAV rather than mp3 so they can be synthesised without an encoder; audioplayers
plays WAV natively. All are optional - a missing file is caught and ignored.
  crash_engine.wav   - looping propeller engine, 2.0 s seamless loop. The screen
                       raises playback rate and volume with the multiplier.
  crash_cashout.wav  - rising G5-C6-G6 flourish on a successful cash out.
  crash_whoosh.wav   - filtered-noise whoosh when the plane flies away.
  crash_bet.wav      - light click when a bet is placed.
  crash_rain.wav     - soft pentatonic chime when a Rain drop appears.

Played from:
  app/lib/screens/games/crash_game_screen.dart  ->  _play() / _startEngineSound()

Asset is wired up in pubspec.yaml under `assets:` as `- assets/sounds/`.
After dropping the file, run:
  flutter pub get
  flutter run
