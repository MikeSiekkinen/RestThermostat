import 'package:flutter/services.dart';

/// Thin haptics helpers shared across interactive widgets per
/// `docs/DESIGN.md` §11.5.
///
/// The first two methods just forward to [HapticFeedback]; they exist so every
/// interactive surface in the app can reference a single import (`haptics.dart`)
/// rather than reaching into `package:flutter/services.dart` from a dozen
/// widgets. The interesting member is [ThrottledSelectionClick], which caps
/// `selectionClick` to the §11.3 ceiling of ≤30/sec for the dial drag.
class Haptics {
  Haptics._();

  /// Light tap — used for mode-pill taps, fan taps, away-chip taps.
  static void light() => HapticFeedback.lightImpact();

  /// Medium tap — used for long-press triggers and schedule-save success.
  static void medium() => HapticFeedback.mediumImpact();
}

/// Selection-click haptic with a per-call minimum-gap throttle.
///
/// The dial fires a `selectionClick` for every tick the user's finger crosses
/// during a drag (DESIGN §11.3). Without throttling, a fast sweep across the
/// 72-tick band would emit dozens of vibrations in tens of milliseconds — both
/// distracting and a quick battery drain on older Android hardware. We cap the
/// emission rate to ~30/sec (one click per 33ms) per the §11.3 spec.
///
/// The throttler is intentionally minimal:
/// - **No tick tracking.** Callers (e.g., the dial) already drop duplicate
///   clicks for the same tick before reaching the throttler.
/// - **Injectable now-source** for deterministic tests. Production uses an
///   internal [Stopwatch]; tests pass a `fake_async`-driven clock.
/// - **Injectable click sink** so tests can record calls without invoking the
///   platform channel.
class ThrottledSelectionClick {
  /// Minimum gap between successive haptics. Defaults to ~33ms (≤30/sec).
  final Duration minGap;

  /// Wall-clock source. Defaults to an internal [Stopwatch].
  final Duration Function() _now;

  /// Click sink. Defaults to [HapticFeedback.selectionClick]. Tests inject a
  /// counter.
  final void Function() _click;

  /// Time of the most recent emitted haptic. `null` until the first emission.
  Duration? _lastEmittedAt;

  ThrottledSelectionClick({
    this.minGap = const Duration(milliseconds: 33),
    Duration Function()? now,
    void Function()? click,
  }) : _now = now ?? _defaultNow(),
       _click = click ?? HapticFeedback.selectionClick;

  /// Try to emit a `selectionClick`. Returns true if the haptic fired, false
  /// if the call was throttled away.
  bool tryClick() {
    final now = _now();
    final last = _lastEmittedAt;
    if (last != null && now - last < minGap) {
      return false;
    }
    _lastEmittedAt = now;
    _click();
    return true;
  }

  /// Reset the throttle window — used by callers that want the next call to
  /// always fire (e.g., the start of a fresh drag gesture).
  void reset() {
    _lastEmittedAt = null;
  }
}

Duration Function() _defaultNow() {
  final sw = Stopwatch()..start();
  return () => sw.elapsed;
}
