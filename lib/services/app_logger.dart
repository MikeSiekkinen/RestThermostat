import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Severity for diagnostic log entries per DESIGN §15.2.
///
/// `info` for routine events (HTTP success, lifecycle transitions, commands),
/// `warn` for recoverable anomalies, `error` for failures/exceptions.
enum LogLevel { info, warn, error }

/// A single diagnostic log entry. Immutable; entries are appended verbatim to
/// the ring buffer and never mutated after creation.
@immutable
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final Map<String, Object?>? data;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.data,
  });

  @override
  bool operator ==(Object other) {
    return other is LogEntry &&
        other.timestamp == timestamp &&
        other.level == level &&
        other.message == message &&
        mapEquals(other.data, data);
  }

  @override
  int get hashCode => Object.hash(timestamp, level, message);
}

/// In-memory ring buffer of recent app events, per DESIGN §15.2.
///
/// Capacity is fixed at [capacity] entries (default 500). On overflow the
/// oldest entry is dropped — order is preserved newest-at-the-end. The buffer
/// is **never persisted** and is cleared when the process exits.
///
/// UI listens via [notifier], which exposes the current snapshot as an
/// immutable list. Each [info]/[warn]/[error] call appends + notifies; if
/// the buffer was full the dropped entry is gone from the next emission.
///
/// **Privacy invariants (load-bearing):**
///
/// - The logger NEVER receives raw `Authorization` header values. Auth presence
///   is logged once at API-client construction time as `"auth: bearer"` /
///   `"auth: basic"` / `"auth: none"` — never the credential itself.
/// - The dio interceptor (see `nle_api_logging_interceptor.dart`) only logs
///   HTTP metadata (method, path, status, duration) — never request or
///   response bodies, which can contain device API keys per the
///   `/api/devices` response schema.
class AppLogger {
  static const int defaultCapacity = 500;

  final int capacity;
  final DateTime Function() _clock;
  final Queue<LogEntry> _entries = Queue<LogEntry>();
  final ValueNotifier<List<LogEntry>> notifier = ValueNotifier(const []);

  AppLogger({this.capacity = defaultCapacity, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Singleton used by production code paths (dio interceptor, lifecycle
  /// bridge, command issuance). Tests can construct their own [AppLogger]
  /// instance and override [appLoggerProvider] to substitute it.
  static final AppLogger instance = AppLogger();

  /// Current buffer contents, oldest-first. Returns a fresh list each call.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  void info(String message, {Map<String, Object?>? data}) =>
      _append(LogLevel.info, message, data);

  void warn(String message, {Map<String, Object?>? data}) =>
      _append(LogLevel.warn, message, data);

  void error(String message, {Map<String, Object?>? data}) =>
      _append(LogLevel.error, message, data);

  /// Logging hook for command issuance per DESIGN §15.2.
  ///
  /// The command-issuing API (`POST /command`) isn't wired yet (issues
  /// #11–#14 will use it); this method exists so those tickets can call it
  /// without re-deriving the message format. Command names and values are
  /// per-spec non-sensitive (e.g., `set_mode`/`heat`, not credentials).
  void commandIssued(String command, Object? value) {
    info('POST /command $command value=$value');
  }

  /// Empties the buffer. UI's "Clear" action calls this after a confirmation
  /// dialog.
  void clear() {
    _entries.clear();
    notifier.value = const [];
  }

  void _append(LogLevel level, String message, Map<String, Object?>? data) {
    _entries.addLast(
      LogEntry(timestamp: _clock(), level: level, message: message, data: data),
    );
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    notifier.value = List.unmodifiable(_entries);
  }
}

/// Riverpod handle for the [AppLogger]. Production resolves to the singleton;
/// tests override with a dedicated instance to assert on captured entries.
final appLoggerProvider = Provider<AppLogger>((_) => AppLogger.instance);
