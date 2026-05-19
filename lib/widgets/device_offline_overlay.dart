import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

/// Dim overlay rendered on top of the home body when the active device is
/// offline (`device.is_available = false`) per `docs/DESIGN.md` §15.1.
///
/// Cached state stays visible underneath at reduced opacity; an
/// [AbsorbPointer] blocks all interaction so writes are disabled until the
/// device returns. A small "Device offline" label sits at the top.
///
/// When [offline] is false the overlay is hidden and pass-through; the child
/// is laid out and reachable normally.
class DeviceOfflineOverlay extends StatelessWidget {
  final bool offline;
  final Widget child;

  const DeviceOfflineOverlay({
    super.key,
    required this.offline,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!offline) return child;
    return Stack(
      children: [
        // Cached UI stays visible at 40% opacity so the user can still see
        // last-known state. AbsorbPointer in front blocks all gestures.
        Opacity(opacity: 0.4, child: AbsorbPointer(child: child)),
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Text(
                AppLocalizations.of(context).deviceOfflineLabel,
                style: EmberTypography.labelSmall(
                  color: EmberColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
