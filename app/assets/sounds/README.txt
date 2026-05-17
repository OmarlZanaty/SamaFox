Drop generated sound files here.

Required file:
  vip_gift.mp3   - plays when a VIP/legendary gift is sent (3-4 seconds)

Played from:
  app/lib/gifts/widgets/gift_animation_overlay.dart  ->  _triggerVip()
    await _vipPlayer.play(AssetSource('sounds/vip_gift.mp3'), volume: 0.9);

Asset is wired up in pubspec.yaml under `assets:` as `- assets/sounds/`.
After dropping the file, run:
  flutter pub get
  flutter run
