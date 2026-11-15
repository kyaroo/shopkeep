import 'dart:developer' as developer;

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
