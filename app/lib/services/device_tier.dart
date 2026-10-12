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

  /// 2–3 GB phones report ~1.8–2.9 GB; 4 GB phones ~3.5 GB.
  static const int _ultraLiteBelowMb = 3300;

  /// Total RAM in MB, null until [init] ran or when the OS would not say.
  static int? totalRamMb;

  /// True on phones that need the room kept light.
  static bool lite = false;

  /// 10/10: phones under 3 GB, on top of [lite]. A 4 GB HONOR was killed on
  /// the home screen at ~800 MB; a 2 GB phone has half that budget, so here
  /// every optional animation goes: mic frames hold their first frame, no
  /// entrance clips (not even the user's own), two gift flights at a time
  /// with small gifts left to the announcement bar, no product videos, and a
  /// 16 MB picture cache. What was bought is still SHOWN — just not animated.
  static bool ultraLite = false;

  /// 11/10: makers whose own memory manager kills a FOREGROUND app far below
  /// what stock Android tolerates. The HONOR NLA-L31 (3.8 GB) was SIGKILLed on
  /// screen six times on 1.0.51 at 300–430 MB, within a minute of launch, after
  /// [lite] had already halved its use. On these, a [lite] phone is treated as
  /// [ultraLite].
  static const Set<String> _strictMakers = {'honor', 'huawei'};

  static Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('deviceRam')
          .timeout(const Duration(seconds: 2));
      if (raw == null) return;
      final total = (raw['totalMb'] as num?)?.toInt();
      totalRamMb = total;
      final mb = total ?? 0;
      lite = raw['lowRam'] == true || (mb > 0 && mb < _liteBelowMb);
      final maker = (raw['maker'] as String?)?.toLowerCase().trim() ?? '';
      ultraLite = raw['lowRam'] == true ||
          (mb > 0 && mb < _ultraLiteBelowMb) ||
          (lite && _strictMakers.contains(maker));
    } catch (e) {
      debugPrint('[DeviceTier] RAM unknown: $e');
    }
  }

  /// For the breadcrumbs: "ram=2861MB lite".
  static String get summary =>
      'ram=${totalRamMb == null ? '?' : '${totalRamMb}MB'}'
      '${ultraLite ? ' ultralite' : lite ? ' lite' : ''}';
}
