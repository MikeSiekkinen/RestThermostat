/// Snapshot of how recently we've been talking to the NLE server, plus any
/// active backoff state. Drives the home-screen stale-state pill per
/// `docs/DESIGN.md` §12.4 and §15.1.
///
/// Construct via [PollingDeviceStateSource.watchStatus]; the source emits a
/// new value whenever any of these fields changes.
class ConnectionStatus {
  /// True when the most recent poll completed within the freshness window
  /// (default 60s) and we're not currently rate-limited.
  final bool isFresh;

  /// True when a poll is in flight AFTER the previous attempt failed — the
  /// pill renders "Reconnecting…" with a spinner in this state.
  final bool isReconnecting;

  /// True when a 429 response told us to back off; [rateLimitedUntil] is the
  /// wall-clock time the backoff expires.
  final bool isRateLimited;

  /// When [isRateLimited] is true, the (clock-time) end of the backoff window.
  /// Null otherwise.
  final DateTime? rateLimitedUntil;

  /// Last successful poll's clock time, or `null` if we've never seen a
  /// successful response (cold start with no cache + first poll failed).
  final DateTime? lastSuccessAt;

  const ConnectionStatus({
    required this.isFresh,
    required this.isReconnecting,
    required this.isRateLimited,
    required this.rateLimitedUntil,
    required this.lastSuccessAt,
  });

  /// Initial state: stale, not reconnecting, no successful poll yet. Used by
  /// the source on construction before the first poll fires.
  static const initial = ConnectionStatus(
    isFresh: false,
    isReconnecting: false,
    isRateLimited: false,
    rateLimitedUntil: null,
    lastSuccessAt: null,
  );

  /// True when the pill should render at all. Hidden when the data is fresh
  /// AND we're not in any of the failure states.
  bool get shouldShowPill => !isFresh || isRateLimited;

  @override
  bool operator ==(Object other) {
    return other is ConnectionStatus &&
        other.isFresh == isFresh &&
        other.isReconnecting == isReconnecting &&
        other.isRateLimited == isRateLimited &&
        other.rateLimitedUntil == rateLimitedUntil &&
        other.lastSuccessAt == lastSuccessAt;
  }

  @override
  int get hashCode => Object.hash(
    isFresh,
    isReconnecting,
    isRateLimited,
    rateLimitedUntil,
    lastSuccessAt,
  );

  @override
  String toString() =>
      'ConnectionStatus(fresh=$isFresh, reconnecting=$isReconnecting, '
      'rateLimited=$isRateLimited until $rateLimitedUntil, '
      'lastSuccessAt=$lastSuccessAt)';
}
