import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'crash_reporter.dart';

/// Lets go of what can be let go of when the phone runs short of memory.
///
/// 10/10: Android's own warning (onTrimMemory "running low") reaches Flutter,
/// which then empties the picture cache — but Android 14+ no longer sends the
/// running-low levels at all, and a HONOR NLA-L31 (Android 15, 4 GB) was killed
/// on the home screen five times in an hour with no warning ever arriving.
/// MainActivity now watches for itself — free system memory against the OS's
/// kill threshold, and on 2–4 GB phones this app's own size — and calls
/// `pressure` here, at most every 30 s.
///
/// What goes: the decoded-picture cache (re-read from disk when needed), and,
/// through [pressure], gift flights, product videos and queued entrance clips.
/// Nothing the user has bought is taken away — only its animation, for now.
class MemoryGuard {
  MemoryGuard._();

  /// Bumped on every warning. Listeners drop their optional, heavy parts.
  static final ValueNotifier<int> pressure = ValueNotifier<int>(0);

  static void install() {
    if (kIsWeb || !Platform.isAndroid) return;
    const MethodChannel('samafox/memory').setMethodCallHandler((call) async {
      if (call.method != 'pressure') return null;
      final a = (call.arguments as Map<Object?, Object?>?) ?? const {};
      final cache = PaintingBinding.instance.imageCache;
      final freedMb = cache.currentSizeBytes >> 20;
      cache.clear();
      CrashReporter.breadcrumb(
        'mem pressure ${a['reason']} avail=${a['availMb']}MB '
        'rss=${a['rssMb']}MB${a['pssMb'] == null ? '' : ' pss=${a['pssMb']}MB'} '
        'freed=${freedMb}MB live=${cache.liveImageCount}',
      );
      pressure.value++;
      return null;
    });
  }
}
