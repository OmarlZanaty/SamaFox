import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:dio/dio.dart';

import 'dio_client.dart';

/// Why the app died, in the app's own words.
///
/// Until this existed there was NOTHING: no Crashlytics, no Sentry, no
/// `FlutterError.onError`, no `PlatformDispatcher.onError`. The report was
/// *"التطبيق يقفل ويرجع للشاشة الرئيسية بعد حوالي دقيقة من دخول الغرفة"* and
/// nobody could say why, because the app kept no record of its own death.
///
/// Two different failures have to be caught, and only one of them is a Dart
/// exception:
///
///  * **Dart errors** — a thrown exception in a widget, a callback or an async
///    gap. Caught by the three handlers [install] registers.
///  * **Process kills** — the Android low-memory killer, or a native crash in
///    libwebrtc. NO Dart handler ever runs for these; the process is simply
///    gone. They are detected AFTERWARDS: every launch writes an "open session"
///    marker and a clean shutdown removes it, so a marker still present on the
///    next launch means the previous session was killed. The breadcrumbs and the
///    resident-memory samples saved beside it say what it was doing and how big
///    it had grown when it happened.
///
/// The second case is the one this app needed, and it is also why this is a
/// file-backed reporter rather than a wrapper around a crash SDK: a report that
/// only exists in memory dies with the process that produced it.
///
/// Reports are uploaded to `POST /api/v1/app/client-report` on the next launch
/// and deleted once accepted. Nothing here ever throws: a reporter that can
/// break the app it reports on is worse than no reporter.
///
/// Adding Crashlytics or Sentry later does not replace this — they catch native
/// stack traces, which this cannot — but it needs the client's own account
/// (a Firebase project and `google-services.json`, or a Sentry DSN). Call
/// [install] before `runApp` either way; the breadcrumbs are what make a native
/// stack trace readable.
class CrashReporter {
  CrashReporter._();

  /// Breadcrumbs kept in memory and flushed to disk. Bounded: this is a ring,
  /// not a log file — the last few hundred events before a death are what
  /// matter, and an unbounded list is its own memory leak.
  static const int _maxBreadcrumbs = 200;
  static final List<String> _breadcrumbs = <String>[];

  // ── live event stream ─────────────────────────────────────────────────────
  //
  // Breadcrumbs answer "what happened before it died". This answers "what is
  // happening right now, on which phone, for which user" — the room joined,
  // the voice engine connected, the microphone re-acquired, the socket dropped,
  // a handled error — batched and posted every ~30s to
  // `POST /api/v1/app/client-events`, where the admin page /client-logs shows
  // it live. An error is posted at once.
  static final List<Map<String, dynamic>> _pending = [];
  static const int _maxQueuedEvents = 300;
  static const int _batchSize = 60;
  static Timer? _eventFlushTimer;
  static bool _eventFlushing = false;
  static int? _userId;
  static int? _roomId;
  static String? _device;
  static final String _sessionId =
      DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
          Random().nextInt(1 << 20).toRadixString(36);

  /// Who this phone belongs to, once known. Called by the auth layer.
  static void setUser(int? id) {
    if (_userId == id) return;
    _userId = id;
    if (id != null) event('auth', 'user $id');
  }

  /// The room events are happening in, so the page can filter by it.
  static void setRoom(int? id) => _roomId = id;

  /// Queue one event. [level] is `error`, `warn` or `info`.
  static void event(
    String kind,
    String message, {
    String level = 'info',
    Map<String, dynamic>? data,
  }) {
    _pending.add(<String, dynamic>{
      't': DateTime.now().toIso8601String(),
      'level': level,
      'kind': kind,
      'msg': message,
      if (_roomId != null) 'room': _roomId,
      if (data != null) 'data': data,
    });
    if (_pending.length > _maxQueuedEvents) {
      // Offline for a while: keep the errors, drop the oldest chatter.
      final errors = _pending.where((e) => e['level'] == 'error').take(100).toList();
      final rest = _pending.where((e) => e['level'] != 'error').toList();
      final keep = (_maxQueuedEvents - errors.length).clamp(0, rest.length);
      _pending
        ..clear()
        ..addAll(errors)
        ..addAll(rest.sublist(rest.length - keep));
    }
    if (level == 'error') {
      unawaited(flushEvents());
    } else {
      _scheduleEventFlush();
    }
  }

  static void _scheduleEventFlush() {
    if (_eventFlushTimer != null) return;
    _eventFlushTimer = Timer(const Duration(seconds: 30), () {
      _eventFlushTimer = null;
      unawaited(flushEvents());
    });
  }

  /// Send what is queued. Called on the timer, on an error, and when the app
  /// goes to the background (the last chance before it may be killed).
  static Future<void> flushEvents() async {
    if (_eventFlushing || _pending.isEmpty) return;
    _eventFlushing = true;
    try {
      while (_pending.isNotEmpty) {
        final batch = _pending.take(_batchSize).toList();
        try {
          final resp = await DioClient.dio.post(
            '/app/client-events',
            data: <String, dynamic>{
              'userId': _userId,
              'appVersion': _appVersion,
              'device': _device,
              'session': _sessionId,
              'events': batch,
            },
            options: Options(
              sendTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ),
          );
          if ((resp.statusCode ?? 500) >= 300) return; // keep, retry later
          _pending.removeRange(0, batch.length);
        } catch (_) {
          return; // offline: keep the queue for the next flush
        }
      }
    } finally {
      _eventFlushing = false;
    }
  }

  static Future<void> _readDevice() async {
    if (kIsWeb) return;
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        _device = '${a.manufacturer} ${a.model} / Android ${a.version.release}';
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        _device = '${i.utsname.machine} / iOS ${i.systemVersion}';
      }
    } catch (_) {}
  }

  static const String _sessionFile = 'samafox_session.json';
  static const String _pendingFile = 'samafox_pending_report.json';

  static Directory? _dir;
  static String _appVersion = 'unknown';
  static bool _installed = false;
  static Timer? _flushTimer;
  static bool _dirty = false;

  /// Highest resident-set-size seen this session, in MB, and the moment it was
  /// seen. This is the measurement that settles whether the app is being killed
  /// for memory — the mesh leak it was written for made it climb steadily.
  static int _peakRssMb = 0;
  static String? _peakRssAt;
  static Timer? _rssTimer;

  /// Install the handlers. Call from `main` before `runApp`, and run `runApp`
  /// inside [guard].
  static Future<void> install() async {
    if (_installed) return;
    _installed = true;

    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      record(
        'FlutterError',
        details.exceptionAsString(),
        details.stack?.toString(),
        library: details.library,
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      record('PlatformDispatcher', error.toString(), stack.toString());
      return true; // handled — reported, and the app carries on
    };

    try {
      _dir = await getApplicationSupportDirectory();
    } catch (e) {
      debugPrint('[CrashReporter] no writable directory: $e');
    }

    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {}

    await _readDevice();
    await _recoverPreviousSession();
    await _markSessionOpen();
    _startRssSampling();
    breadcrumb('app start $_appVersion');
  }

  /// Runs [body] in a zone that catches everything escaping it, so an error
  /// thrown outside the Flutter callbacks is recorded rather than lost.
  static void guard(void Function() body) {
    runZonedGuarded(body, (error, stack) {
      record('uncaught', error.toString(), stack.toString());
    });
  }

  /// Note something that happened. Cheap, synchronous, bounded.
  ///
  /// Keep these SHORT and factual — "room 12 enter", "peer 88 created
  /// (total 9)". They are read in a list after the fact, and their value is the
  /// sequence, not the prose.
  static void breadcrumb(String message) {
    final line = '${DateTime.now().toIso8601String()} $message';
    _breadcrumbs.add(line);
    if (_breadcrumbs.length > _maxBreadcrumbs) {
      _breadcrumbs.removeRange(0, _breadcrumbs.length - _maxBreadcrumbs);
    }
    _dirty = true;
    _scheduleFlush();
    if (kDebugMode) debugPrint('🧭 $message');
    event('crumb', message);
  }

  /// Record an error, with the breadcrumbs that led to it.
  static void record(
    String kind,
    String message,
    String? stack, {
    String? library,
  }) {
    debugPrint('💥 [$kind] $message');
    final report = <String, dynamic>{
      'kind': kind,
      'message': message,
      'library': library,
      'stack': stack,
      'at': DateTime.now().toIso8601String(),
      ..._context(),
    };
    // Written immediately: an error is often the last thing to happen before the
    // process goes away, so there may be no later chance to save it.
    unawaited(_writePending(report));
    unawaited(_upload(report));
    event(
      kind,
      message.length > 300 ? '${message.substring(0, 300)}…' : message,
      level: 'error',
      data: {'stack': stack?.split('\n').take(8).join('\n')},
    );
  }

  /// Everything about this session that helps read a report.
  static Map<String, dynamic> _context() => <String, dynamic>{
        'appVersion': _appVersion,
        'platform': _platformName(),
        'peakRssMb': _peakRssMb,
        'peakRssAt': _peakRssAt,
        'rssMb': _rssMb(),
        'breadcrumbs': List<String>.from(_breadcrumbs),
      };

  static String _platformName() {
    if (kIsWeb) return 'web';
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Resident memory in MB, or null where the platform will not say.
  static int? _rssMb() {
    if (kIsWeb) return null;
    try {
      final rss = ProcessInfo.currentRss;
      if (rss <= 0) return null;
      return (rss / (1024 * 1024)).round();
    } catch (_) {
      return null;
    }
  }

  /// Sample memory while the app runs.
  ///
  /// Every 15 seconds is enough to see a climb and cheap enough to ignore. The
  /// peak is what ends up in the report: a kill leaves no time to measure
  /// anything, so the last high-water mark is the evidence.
  static void _startRssSampling() {
    _rssTimer?.cancel();
    void sample() {
      final mb = _rssMb();
      if (mb == null) return;
      if (mb > _peakRssMb) {
        _peakRssMb = mb;
        _peakRssAt = DateTime.now().toIso8601String();
        // Only the milestones, or this becomes the noisiest breadcrumb there is.
        if (mb % 100 < 15) breadcrumb('rss ~${mb}MB');
      }
    }

    sample();
    _rssTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      sample();
      _dirty = true;
      _scheduleFlush();
    });
  }

  // ── session marker ────────────────────────────────────────────────────────

  static File? _file(String name) {
    final dir = _dir;
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  static Future<void> _markSessionOpen() async {
    await _flushSession();
  }

  /// Write the session marker. Debounced: breadcrumbs arrive in bursts and this
  /// must never become the app's busiest disk writer.
  static void _scheduleFlush() {
    if (_flushTimer != null) return;
    _flushTimer = Timer(const Duration(seconds: 3), () {
      _flushTimer = null;
      if (!_dirty) return;
      _dirty = false;
      unawaited(_flushSession());
    });
  }

  static Future<void> _flushSession() async {
    final f = _file(_sessionFile);
    if (f == null) return;
    try {
      await f.writeAsString(jsonEncode(<String, dynamic>{
        'openedAt': DateTime.now().toIso8601String(),
        ..._context(),
      },),);
    } catch (e) {
      debugPrint('[CrashReporter] session write failed: $e');
    }
  }

  /// Called on a deliberate shutdown (the app being detached). Removing the
  /// marker is what makes its PRESENCE on the next launch meaningful.
  static Future<void> markCleanExit() async {
    await flushEvents();
    _flushTimer?.cancel();
    _flushTimer = null;
    _rssTimer?.cancel();
    _rssTimer = null;
    final f = _file(_sessionFile);
    if (f == null) return;
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// A leftover session marker means the previous run was killed without ever
  /// reaching a Dart handler — the low-memory killer or a native crash. Turn it
  /// into a report and try to send it.
  static Future<void> _recoverPreviousSession() async {
    final f = _file(_sessionFile);
    if (f == null) return;
    try {
      if (await f.exists()) {
        final raw = await f.readAsString();
        await f.delete();
        final data = jsonDecode(raw);
        if (data is Map) {
          final report = <String, dynamic>{
            'kind': 'processKilled',
            'message':
                'previous session ended without a clean shutdown (OS kill or native crash)',
            'at': DateTime.now().toIso8601String(),
            'previousSession': data,
          };
          debugPrint('💥 [CrashReporter] previous session was killed '
              '(peak RSS ${data['peakRssMb']}MB)');
          await _writePending(report);
        }
      }
    } catch (e) {
      debugPrint('[CrashReporter] recovery failed: $e');
    }

    // Anything that could not be sent last time goes now — but NOT on the
    // startup path. Uploading here would make every cold start wait on a POST
    // with a 30-second timeout, so a phone on a bad network would stare at the
    // splash screen because of a crash report. It is already safe on disk;
    // sending it a few seconds late costs nothing.
    Timer(const Duration(seconds: 5), () => unawaited(_flushPending()));
  }

  // ── delivery ──────────────────────────────────────────────────────────────

  /// Reports waiting for a network. Capped at the newest few: a phone that
  /// cannot reach the server for a week must not accumulate a report file.
  static const int _maxPending = 10;

  static Future<void> _writePending(Map<String, dynamic> report) async {
    final f = _file(_pendingFile);
    if (f == null) return;
    try {
      final list = await _readPending();
      list.add(report);
      if (list.length > _maxPending) {
        list.removeRange(0, list.length - _maxPending);
      }
      await f.writeAsString(jsonEncode(list));
    } catch (e) {
      debugPrint('[CrashReporter] pending write failed: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> _readPending() async {
    final f = _file(_pendingFile);
    if (f == null) return <Map<String, dynamic>>[];
    try {
      if (!await f.exists()) return <Map<String, dynamic>>[];
      final data = jsonDecode(await f.readAsString());
      if (data is List) {
        return data.whereType<Map>().map(Map<String, dynamic>.from).toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  static Future<void> _flushPending() async {
    final pending = await _readPending();
    if (pending.isEmpty) return;
    final unsent = <Map<String, dynamic>>[];
    for (final report in pending) {
      final ok = await _upload(report, persistOnFailure: false);
      if (!ok) unsent.add(report);
    }
    final f = _file(_pendingFile);
    if (f == null) return;
    try {
      if (unsent.isEmpty) {
        if (await f.exists()) await f.delete();
      } else {
        await f.writeAsString(jsonEncode(unsent));
      }
    } catch (_) {}
  }

  /// Best-effort upload. Returns true when the server took it.
  static Future<bool> _upload(
    Map<String, dynamic> report, {
    bool persistOnFailure = true,
  }) async {
    try {
      final resp = await DioClient.dio.post(
        '/app/client-report',
        data: report,
      );
      final ok = (resp.statusCode ?? 500) < 300;
      if (ok) await _forgetPending(report);
      return ok;
    } catch (e) {
      // Offline, or the endpoint is not deployed yet. The report is already on
      // disk and goes out on a later launch.
      debugPrint('[CrashReporter] upload deferred: $e');
      if (persistOnFailure) await _writePending(report);
      return false;
    }
  }

  /// Drop a report that has been accepted, matching on its timestamp+kind.
  static Future<void> _forgetPending(Map<String, dynamic> report) async {
    final f = _file(_pendingFile);
    if (f == null) return;
    try {
      final list = await _readPending();
      list.removeWhere(
        (r) => r['at'] == report['at'] && r['kind'] == report['kind'],
      );
      if (list.isEmpty) {
        if (await f.exists()) await f.delete();
      } else {
        await f.writeAsString(jsonEncode(list));
      }
    } catch (_) {}
  }
}
