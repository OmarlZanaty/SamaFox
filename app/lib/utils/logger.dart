import 'package:logger/logger.dart';

import '../services/crash_reporter.dart';

class AppLogger {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 80,
      colors: true,
      printEmojis: true,
      printTime: true,
    ),
  );

  static void debug(String message) {
    _logger.d(message);
  }

  static void info(String message) {
    _logger.i(message);
  }

  static void warning(String message) {
    _logger.w(message);
    // Warnings and errors also reach the server's client log (see
    // CrashReporter): a warning printed on a phone nobody is watching is not a
    // warning anyone can act on.
    CrashReporter.event('log', message, level: 'warn');
  }

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
    CrashReporter.event(
      'log',
      error == null ? message : '$message: $error',
      level: 'error',
      data: stackTrace == null
          ? null
          : {'stack': stackTrace.toString().split('\n').take(6).join('\n')},
    );
  }
}
