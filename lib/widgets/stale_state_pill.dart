import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../state/connection_status.dart';
import '../state/providers.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

/// Home-screen stale-state surface per `docs/DESIGN.md` §12.4 + §15.1.
///
/// Renders nothing when the connection is fresh. Switches between three
/// visible states via [AnimatedSwitcher] (200ms `easeOut` per DESIGN §11.4):
///
/// - **Stale** — "Last updated 3 min ago" + Retry button. Subtle pill.
/// - **Reconnecting** — small spinner + "Reconnecting…". Active retry path.
/// - **Rate-limited** — "Server busy — retrying" with optional remaining
///   duration. Set when the source receives a 429.
///
/// The pill consumes [connectionStatusProvider] and calls
/// [DeviceStateSource.refresh] on the Retry tap. Hidden entirely while the
/// status is fresh — collapses to zero height so the layout above the dial
/// doesn't shift when reconnection succeeds.
class StaleStatePill extends ConsumerWidget {
  /// `now()` injection for relative-time formatting ("3 min ago"). Defaults
  /// to [DateTime.now] in production; widget tests pass a deterministic clock
  /// so the rendered copy is asserted.
  final DateTime Function() now;

  const StaleStatePill({super.key, this.now = DateTime.now});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncStatus = ref.watch(connectionStatusProvider);
    final status = asyncStatus.maybeWhen(
      data: (s) => s,
      orElse: () => ConnectionStatus.initial,
    );

    final child = _buildChild(context, ref, status);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      child: child,
    );
  }

  Widget _buildChild(
    BuildContext context,
    WidgetRef ref,
    ConnectionStatus status,
  ) {
    final l = AppLocalizations.of(context);
    if (!status.shouldShowPill) {
      // SizedBox.shrink would collapse to zero, but a keyed shrink with a
      // height-stable wrapper lets AnimatedSwitcher cross-fade cleanly.
      return const SizedBox(key: ValueKey('fresh'), height: 0);
    }
    if (status.isRateLimited) {
      return _Pill(
        key: const ValueKey('rate-limited'),
        text: l.stalePillRateLimited,
        leading: const _Spinner(),
      );
    }
    if (status.isReconnecting) {
      return _Pill(
        key: const ValueKey('reconnecting'),
        text: l.stalePillReconnecting,
        leading: const _Spinner(),
      );
    }
    return _Pill(
      key: const ValueKey('stale'),
      text: _staleCopy(context, status.lastSuccessAt),
      trailing: TextButton(
        onPressed: () => ref.read(deviceStateSourceProvider).refresh(),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          l.stalePillRetry,
          style: EmberTypography.labelSmall(color: EmberColors.textPrimary),
        ),
      ),
    );
  }

  String _staleCopy(BuildContext context, DateTime? lastSuccessAt) {
    final l = AppLocalizations.of(context);
    if (lastSuccessAt == null) return l.stalePillNotConnected;
    final elapsed = now().difference(lastSuccessAt);
    return l.stalePillLastUpdated(_formatElapsed(context, elapsed));
  }

  /// Format a "Xs ago" / "Xm ago" / "Xh ago" string. Intentionally
  /// approximate — the pill isn't a stopwatch, and rounding to the nearest
  /// minute past 60s avoids the seconds counter ticking visibly.
  static String _formatElapsed(BuildContext context, Duration d) {
    final l = AppLocalizations.of(context);
    if (d.inSeconds < 60) return l.stalePillElapsedJustNow;
    if (d.inMinutes < 2) return l.stalePillElapsedOneMinute;
    if (d.inHours < 1) return l.stalePillElapsedMinutes(d.inMinutes);
    if (d.inHours < 2) return l.stalePillElapsedOneHour;
    return l.stalePillElapsedHours(d.inHours);
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Widget? leading;
  final Widget? trailing;

  const _Pill({super.key, required this.text, this.leading, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.10),
            width: 1,
          ),
        ),
        padding: EdgeInsets.only(
          left: leading == null ? 14 : 10,
          right: trailing == null ? 14 : 6,
          top: 6,
          bottom: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 8)],
            Flexible(
              child: Text(
                text,
                style: EmberTypography.labelSmall(
                  color: EmberColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(
        strokeWidth: 1.5,
        valueColor: AlwaysStoppedAnimation(EmberColors.textSecondary),
      ),
    );
  }
}
