import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Log levels for filtering logs
enum LogLevel {
  none(0),    // No logs
  error(1),   // Only errors
  warning(2), // Errors and warnings
  info(3),    // Errors, warnings, and info
  debug(4);   // All logs including debug

  final int value;
  const LogLevel(this.value);

  static LogLevel fromString(String? level) {
    switch (level?.toLowerCase()) {
      case 'none':
        return LogLevel.none;
      case 'error':
        return LogLevel.error;
      case 'warning':
        return LogLevel.warning;
      case 'info':
        return LogLevel.info;
      case 'debug':
        return LogLevel.debug;
      default:
        return LogLevel.info; // Default to info
    }
  }
}

/// Log utility with configurable levels via .env
class Log {
  static LogLevel? _logLevel;
  
  static LogLevel get logLevel {
    _logLevel ??= LogLevel.fromString(dotenv.env['LOG_LEVEL']);
    return _logLevel!;
  }

  /// Set log level programmatically (useful for testing)
  static void setLogLevel(LogLevel level) {
    _logLevel = level;
  }

  /// Log debug message (lowest priority)
  static void d(String message, [String? tag]) {
    if (logLevel.value >= LogLevel.debug.value) {
      final prefix = tag != null ? '🐛 [$tag]' : '🐛';
      debugPrint('$prefix $message');
    }
  }

  /// Log info message
  static void i(String message, [String? tag]) {
    if (logLevel.value >= LogLevel.info.value) {
      final prefix = tag != null ? 'ℹ️ [$tag]' : 'ℹ️';
      debugPrint('$prefix $message');
    }
  }

  /// Log warning message
  static void w(String message, [String? tag]) {
    if (logLevel.value >= LogLevel.warning.value) {
      final prefix = tag != null ? '⚠️ [$tag]' : '⚠️';
      debugPrint('$prefix $message');
    }
  }

  /// Log error message (highest priority)
  static void e(String message, [String? tag, Object? error]) {
    if (logLevel.value >= LogLevel.error.value) {
      final prefix = tag != null ? '❌ [$tag]' : '❌';
      debugPrint('$prefix $message');
      if (error != null) {
        debugPrint('  Error details: $error');
      }
    }
  }

  /// Log success message (shown at info level)
  static void s(String message, [String? tag]) {
    if (logLevel.value >= LogLevel.info.value) {
      final prefix = tag != null ? '✅ [$tag]' : '✅';
      debugPrint('$prefix $message');
    }
  }
}






