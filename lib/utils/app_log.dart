import 'dart:developer' as developer;

import 'package:flutter/services.dart';

/// Host-side log, so a **release** build is diagnosable: `dart:developer` is
/// compiled out in release, but Android's logcat still receives this.
const MethodChannel _hostLog = MethodChannel('myhanout/view');

/// Records an operational event on the host (logcat tag `MainActivity`).
///
/// Never throws and never includes payload content or URIs — only short,
/// operator-readable outcomes such as a completed sale or an applied import.
void logInfo(String message) {
  _hostLog.invokeMethod<void>('log', {'message': message}).catchError((_) {});
}

/// Structured, non-throwing logging for background work.
///
/// `dart:developer`'s [developer.log] writes to the platform log / DevTools and
/// keeps the error and stack trace as separate fields, so a crash reporter (or
/// the debug console) can read them instead of parsing one interpolated string.
/// Never use `print` in `lib/` — it is unbuffered, unstructured and flagged by
/// `avoid_print`.
void logWarning(String message, {Object? error, StackTrace? stackTrace}) {
  developer.log(
    message,
    level: 900,
    error: error,
    stackTrace: stackTrace,
  );
}
