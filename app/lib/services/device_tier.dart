import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// How much the phone can take.
///
/// 05/10: two room owners — an OPPO A15 (Android 10) and a Samsung A30 — were
/// thrown out of their own room many times a day, the A30 by the OS's
/// low-memory killer while on screen, within half a minute of entering, while
/// phones with more RAM sat in the same room for hours. A room holds hundreds
/// of MB of graphics memory (decoded pictures, video decoders, gift flights);
/// on a 2–4 GB phone that is the whole budget. [lite] turns the optional parts
/// down for those phones: fewer decoders, fewer flights, a smaller picture
/// cache. Nothing a user paid for disappears for anyone else.
class DeviceTier {
  DeviceTier._();

  static const MethodChannel _channel = MethodChannel('samafox/memory');

  /// Phones with at most 4 GB report a total of roughly 3.5–3.8 GB (the kernel
  /// keeps the rest); 6 GB phones report ~5.5 GB.
  static const int _liteBelowMb = 4500;

  /// Total RAM in MB, null until [init] ran or when the OS would not say.
  static int? totalRamMb;

  /// True on phones that need the room kept light.
  static bool lite = false;

  static Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('deviceRam')
          .timeout(const Duration(seconds: 2));
      if (raw == null) return;
      final total = (raw['totalMb'] as num?)?.toInt();
      totalRamMb = total;
      lite = raw['lowRam'] == true || (total != null && total > 0 && total < _liteBelowMb);
    } catch (e) {
      debugPrint('[DeviceTier] RAM unknown: $e');
    }
  }

  /// For the breadcrumbs: "ram=2861MB lite".
  static String get summary =>
      'ram=${totalRamMb == null ? '?' : '${totalRamMb}MB'}${lite ? ' lite' : ''}';
}
