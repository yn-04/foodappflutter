import 'package:flutter/foundation.dart';

/// Unified logger for debug build; no-op in release.
void logDebug(Object? message, {StackTrace? stackTrace}) {
  if (!kDebugMode) return;
  if (stackTrace != null) {
    debugPrint('$message\n$stackTrace');
  } else {
    debugPrint('$message');
  }
}
