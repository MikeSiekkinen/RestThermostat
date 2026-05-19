import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cross-cutting signal that bubbles up from the API client when an
/// authentication failure (401/403) is observed during a command write or a
/// background poll. The home shell listens to this and surfaces a snackbar
/// with "Open Settings" so the user can re-enter credentials per
/// `docs/DESIGN.md` §15.1.
///
/// Why a notifier instead of a snackbar at the catch site? Two reasons:
/// 1. **Deep-link.** The snackbar needs a Navigator that can push the
///    Settings screen with the Auth section pre-expanded; that's a host
///    concern, not the widget's.
/// 2. **De-duplication.** During a background poll loop a 401 can fire
///    repeatedly. The coordinator coalesces by ignoring repeat fires within
///    [_throttle]; the host only shows one snackbar per "incident."
class AuthFailureCoordinator extends ChangeNotifier {
  static const _throttle = Duration(seconds: 30);

  final DateTime Function() _clock;
  DateTime? _lastFiredAt;

  AuthFailureCoordinator({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Public for tests so they can probe the throttle window directly.
  @visibleForTesting
  DateTime? get lastFiredAt => _lastFiredAt;

  /// Signal a fresh auth failure. Throttled — calls within [_throttle] of the
  /// last fire are dropped silently so an auth-broken polling loop doesn't
  /// stack snackbars on top of each other.
  void fire() {
    final now = _clock();
    final last = _lastFiredAt;
    if (last != null && now.difference(last) < _throttle) return;
    _lastFiredAt = now;
    notifyListeners();
  }

  /// Reset the throttle. Called by the host after the user opens the Settings
  /// deep-link, so the next failure can re-fire without waiting out the full
  /// window.
  void reset() {
    _lastFiredAt = null;
  }
}

/// Riverpod handle. Survives the lifetime of the app; the home shell wires it
/// to a [SnackBar] via [ChangeNotifier.addListener].
final authFailureCoordinatorProvider = Provider<AuthFailureCoordinator>(
  (_) => AuthFailureCoordinator(),
);
