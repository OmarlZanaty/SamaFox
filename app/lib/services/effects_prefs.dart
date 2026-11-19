import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SPEC52 #23 — "تأثيرات الهدايا" / "تأثيرات الدخول" for THIS user only.
///
/// Display choices, stored on the phone. The gift / entrance events still
/// arrive from the server and still update balances, seat totals, CP and the
/// chat log — only the animation is not drawn. Nobody else is affected.
class EffectsPrefs {
  EffectsPrefs._();
  static final EffectsPrefs instance = EffectsPrefs._();

  static const _giftKey = 'fx_gift_effects_on';
  static const _entryKey = 'fx_entry_effects_on';
  static const _giftSoundKey = 'fx_gift_sounds_on';
  static const _entrySoundKey = 'fx_entry_sounds_on';

  final ValueNotifier<bool> giftEffects = ValueNotifier<bool>(true);
  final ValueNotifier<bool> entryEffects = ValueNotifier<bool>(true);
  final ValueNotifier<bool> giftSoundsOn = ValueNotifier<bool>(true);
  final ValueNotifier<bool> entrySoundsOn = ValueNotifier<bool>(true);
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      giftEffects.value = p.getBool(_giftKey) ?? true;
      entryEffects.value = p.getBool(_entryKey) ?? true;
      giftSoundsOn.value = p.getBool(_giftSoundKey) ?? true;
      entrySoundsOn.value = p.getBool(_entrySoundKey) ?? true;
    } catch (e) {
      debugPrint('[EffectsPrefs] load failed: $e');
    }
  }

  Future<void> setGiftEffects(bool on) async {
    giftEffects.value = on;
    try {
      (await SharedPreferences.getInstance()).setBool(_giftKey, on);
    } catch (_) {}
  }

  Future<void> setGiftSounds(bool on) async {
    giftSoundsOn.value = on;
    try {
      await (await SharedPreferences.getInstance()).setBool(_giftSoundKey, on);
    } catch (_) {}
  }

  Future<void> setEntrySounds(bool on) async {
    entrySoundsOn.value = on;
    try {
      await (await SharedPreferences.getInstance()).setBool(_entrySoundKey, on);
    } catch (_) {}
  }

  Future<void> setEntryEffects(bool on) async {
    entryEffects.value = on;
    try {
      (await SharedPreferences.getInstance()).setBool(_entryKey, on);
    } catch (_) {}
  }
}
