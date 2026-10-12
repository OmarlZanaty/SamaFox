import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// F4 — the one place the app decides "which phone is this".
///
/// Android: ANDROID_ID from the platform channel. NOT `androidInfo.id` — that
/// is Build.ID, the firmware build ("AP3A.240905.015.A2"), identical on every
/// phone of the same model and update, so a device ban on it locked out
/// strangers. iOS: identifierForVendor, which is already per device.
class DeviceIdentity {
  static const _channel = MethodChannel('samafox/device');

  /// Resolved once and kept: callers sit in front of every request.
  static String? _cached;

  static Future<String?> get() async {
    if (_cached != null) return _cached;
    try {
      if (kIsWeb) return _cached = 'web';
      if (Platform.isAndroid) {
        final id = await _channel.invokeMethod<String>('androidId');
        if (id != null && id.isNotEmpty) _cached = id;
      } else if (Platform.isIOS) {
        _cached = (await DeviceInfoPlugin().iosInfo).identifierForVendor;
      }
    } catch (_) {
      // A device that will not identify itself is still allowed to use the
      // app — the IP half of a ban still applies to it.
    }
    return _cached;
  }
}
