import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_tier.dart';

/// 23/10: Skia keeps offscreen textures after room effects finish. Limit that
/// cache by device tier and drop unlocked resources on memory pressure.
class GpuCache {
  GpuCache._();

  static bool _purging = false;

  static int get budgetBytes =>
      (DeviceTier.ultraLite
          ? 48
          : DeviceTier.lite
              ? 64
              : 128) <<
      20;

  static Future<void> _setBudget(int bytes) async {
    if (kIsWeb) return;
    try {
      await SystemChannels.skia.invokeMethod<void>(
        'Skia.setResourceCacheMaxBytes',
        bytes,
      );
    } catch (_) {
      // Other renderers and platforms may not handle the Skia channel.
    }
  }

  static Future<void> apply() => _setBudget(budgetBytes);

  static Future<void> purge() async {
    if (kIsWeb || _purging) return;
    _purging = true;
    try {
      await _setBudget(8 << 20);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await apply();
    } catch (_) {
      // Memory cleanup must never interrupt the app.
    } finally {
      _purging = false;
    }
  }
}
