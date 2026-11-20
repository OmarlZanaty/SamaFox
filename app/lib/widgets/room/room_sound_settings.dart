import 'dart:async';
import 'package:flutter/material.dart';
import '../../repositories/room_repository.dart';
import '../../services/effects_prefs.dart';

/// Room policy is separate from the user's saved preferences.
class RoomSoundSettings extends ChangeNotifier {
  RoomSoundSettings(this.roomId, {this.poll = true}) {
    EffectsPrefs.instance.giftSoundsOn.addListener(_changed);
    EffectsPrefs.instance.entrySoundsOn.addListener(_changed);
    if (poll) {
      unawaited(refresh());
      // The sound-settings endpoint currently sends no socket notification.
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => refresh());
    }
  }

  final int roomId;
  final bool poll;
  Timer? _timer;
  bool _disposed = false;
  Future<void>? _pending;
  bool _loaded = false;
  int _revision = 0;
  bool muteGiftSounds = false;
  bool muteEntranceSounds = false;
  bool get giftSoundsOn => _loaded && !muteGiftSounds &&
      EffectsPrefs.instance.giftSoundsOn.value;
  bool get entrySoundsOn => _loaded && !muteEntranceSounds &&
      EffectsPrefs.instance.entrySoundsOn.value;

  void _changed() { if (!_disposed) notifyListeners(); }

  void update({required bool giftsMuted, required bool entranceMuted}) {
    if (_disposed) return;
    _revision++;
    _loaded = true;
    muteGiftSounds = giftsMuted;
    muteEntranceSounds = entranceMuted;
    notifyListeners();
  }

  Future<void> refresh() => _pending ??= _fetch().whenComplete(() => _pending = null);

  Future<void> _fetch() async {
    final revision = _revision;
    try {
      final result = await RoomRepository().getRoomById(roomId);
      final room = result.data;
      if (!_disposed && revision == _revision && result.isSuccess && room != null) {
        update(giftsMuted: room.giftSoundsMuted,
            entranceMuted: room.entranceSoundsMuted);
      }
    } catch (e) {
      debugPrint('[RoomSoundSettings] refresh failed: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    EffectsPrefs.instance.giftSoundsOn.removeListener(_changed);
    EffectsPrefs.instance.entrySoundsOn.removeListener(_changed);
    super.dispose();
  }
}

class RoomSoundScope extends InheritedWidget {
  const RoomSoundScope({super.key, required this.settings, required super.child});
  final RoomSoundSettings settings;
  static RoomSoundSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RoomSoundScope>()!.settings;
  @override
  bool updateShouldNotify(RoomSoundScope oldWidget) => settings != oldWidget.settings;
}
