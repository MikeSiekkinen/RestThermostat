import 'connection_status.dart';
import 'devices_snapshot.dart';

/// DESIGN §3.2 — the seam the UI talks to. v1 ships a polling impl; an SSE
/// impl can slot in later without UI changes.
abstract class DeviceStateSource {
  /// Broadcast stream of the latest device state. Late subscribers receive
  /// the most recent value on subscribe.
  Stream<DevicesSnapshot> watch();

  /// Broadcast stream of connection-state transitions (DESIGN §12.4 + §15.1).
  /// Drives the home-screen stale-state pill: fresh / reconnecting /
  /// rate-limited / stale. Late subscribers receive the current status on
  /// subscribe.
  Stream<ConnectionStatus> watchStatus();

  /// Pull-to-refresh / post-command / on-resume. Fetches immediately and
  /// schedules reconciliation polls per DESIGN §3.3.
  void refresh();

  /// True when the last successful poll is older than the freshness window,
  /// or when the most recent attempt failed.
  bool get isStale;

  /// Stop polling and release resources.
  Future<void> dispose();
}
