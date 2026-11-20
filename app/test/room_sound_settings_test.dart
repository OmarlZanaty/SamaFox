import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/services/effects_prefs.dart';
import 'package:samafox/widgets/room/room_sound_settings.dart';

void main() {
  test('room mutes combine with personal preferences without overwriting them', () {
    final prefs = EffectsPrefs.instance;
    final oldGift = prefs.giftSoundsOn.value;
    final oldEntry = prefs.entrySoundsOn.value;
    final settings = RoomSoundSettings(1, poll: false);
    addTearDown(() {
      settings.dispose();
      prefs.giftSoundsOn.value = oldGift;
      prefs.entrySoundsOn.value = oldEntry;
    });
    prefs.giftSoundsOn.value = true;
    prefs.entrySoundsOn.value = true;
    // Playback stays silent until the room policy has loaded.
    expect(settings.giftSoundsOn, isFalse);
    expect(settings.entrySoundsOn, isFalse);
    settings.update(giftsMuted: true, entranceMuted: false);
    expect(settings.giftSoundsOn, isFalse);
    expect(settings.entrySoundsOn, isTrue);
    expect(prefs.giftSoundsOn.value, isTrue);
    settings.update(giftsMuted: false, entranceMuted: true);
    expect(settings.giftSoundsOn, isTrue);
    expect(settings.entrySoundsOn, isFalse);
    expect(prefs.entrySoundsOn.value, isTrue);
    prefs.giftSoundsOn.value = false;
    prefs.entrySoundsOn.value = false;
    settings.update(giftsMuted: false, entranceMuted: false);
    expect(settings.giftSoundsOn, isFalse);
    expect(settings.entrySoundsOn, isFalse);
  });

  test('active playback listeners receive policy and personal changes', () {
    final prefs = EffectsPrefs.instance;
    final old = prefs.giftSoundsOn.value;
    prefs.giftSoundsOn.value = true;
    final settings = RoomSoundSettings(1, poll: false);
    addTearDown(() {
      settings.dispose();
      prefs.giftSoundsOn.value = old;
    });
    final heard = <bool>[];
    settings.addListener(() => heard.add(settings.giftSoundsOn));
    settings.update(giftsMuted: false, entranceMuted: false);
    settings.update(giftsMuted: true, entranceMuted: false);
    settings.update(giftsMuted: false, entranceMuted: false);
    prefs.giftSoundsOn.value = false;
    expect(heard, [true, false, true, false]);
  });
}
