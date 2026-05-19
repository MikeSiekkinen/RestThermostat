import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/device.dart';
import '../theme/colors.dart';

/// Derived single-glance device status per `docs/DESIGN.md` §9.2.
///
/// Captures the union of what the user wants the system to do (`mode`) and
/// what the system is currently doing (`hvac` block). Used by the home-screen
/// status row and the pulsing-dot indicator.
enum DeviceStatus {
  heating,
  cooling,
  fanOnly,
  idle,
  off;

  /// Display label rendered next to the pulsing dot. Pulls from
  /// AppLocalizations so the screen reader + visible text stays in the
  /// configured locale.
  String label(BuildContext context) {
    final l = AppLocalizations.of(context);
    return switch (this) {
      heating => l.statusHeating,
      cooling => l.statusCooling,
      fanOnly => l.statusFanOnly,
      idle => l.statusIdle,
      off => l.statusOff,
    };
  }

  /// Color of the pulsing dot in the status row.
  ///
  /// Heating/cooling get their mode accent so the row matches the background
  /// gradient at a glance. Fan-only is silver-ish white-grey (matches the fan
  /// widget's "active" treatment in §10.2). Idle / off are dimmed white so
  /// they read as "alive but quiet" rather than disconnected.
  Color get dotColor => switch (this) {
    heating => EmberColors.heatGlow,
    cooling => EmberColors.coolGlow,
    fanOnly => const Color(0xFFD8DEE8),
    idle => EmberColors.textTertiary,
    off => EmberColors.textTertiary,
  };
}

/// Derive [DeviceStatus] from a [Device] snapshot per the table in DESIGN §9.2.
///
/// Precedence: `heater`/`ac` always win when active — they describe what the
/// equipment is *currently doing*, not what the user wants. After ruling those
/// out we look at the fan; whatever falls through is either `idle` (when a
/// heating/cooling mode is selected but inactive) or `off` (when the device
/// is fully off and not even fanning).
///
/// `emergency` mode is not in the §9.2 table — it isn't surfaced in v1 — so
/// it falls into the same "no hvac, no fan → idle" bucket as `heat`/`cool`.
DeviceStatus deriveStatus(Device d) {
  if (d.hvac.heater) return DeviceStatus.heating;
  if (d.hvac.ac) return DeviceStatus.cooling;
  if (d.mode == DeviceMode.off) {
    return d.hvac.fan ? DeviceStatus.fanOnly : DeviceStatus.off;
  }
  return d.hvac.fan ? DeviceStatus.fanOnly : DeviceStatus.idle;
}
