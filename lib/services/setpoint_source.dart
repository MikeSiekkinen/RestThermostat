import 'package:flutter/widgets.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/device.dart';
import '../models/schedule.dart';
import '../widgets/temperature_dial.dart';
import 'schedule_helpers.dart';

/// Where the device's current setpoint came from, per `docs/DESIGN.md` §9.5.
///
/// Displayed on the Details screen below the target temperature. Computed
/// locally — NLE doesn't surface a "source" field directly, so we infer:
///
/// 1. If the device is away → `away`.
/// 2. Otherwise, if the schedule's currently-active event has a `targetTemp`
///    that matches the device's `target_temperature` (within a half-tick
///    epsilon to forgive server-side rounding) → `scheduled`.
/// 3. Otherwise → `manual`.
///
/// Fuzziness: a manual write to the exact scheduled value will read as
/// `scheduled`. DESIGN §9.5 calls this out and accepts it for v1.
enum SetpointSource {
  away,
  scheduled,
  manual;

  /// Localized subtitle rendered under the Setpoint stat tile on Details.
  String label(BuildContext context) {
    final l = AppLocalizations.of(context);
    return switch (this) {
      away => l.detailsSetpointSourceAway,
      scheduled => l.detailsSetpointSourceScheduled,
      manual => l.detailsSetpointSourceManual,
    };
  }
}

/// Half-a-tick on the temperature dial, used as the comparison epsilon for
/// matching the schedule event's target against the device's current target.
/// At 72 ticks over `[4.5, 32]°C` this is ~0.19°C.
const double _matchEpsilonC =
    (TemperatureDial.maxCelsius - TemperatureDial.minCelsius) /
    (TemperatureDial.tickCount - 1) /
    2;

/// Derive the current setpoint source per DESIGN §9.5. `now` is injectable
/// so the helper is deterministic in tests; production callers pass
/// [DateTime.now].
SetpointSource deriveSetpointSource({
  required Device device,
  required Schedule? schedule,
  required DateTime now,
}) {
  if (device.isAway) return SetpointSource.away;
  if (schedule == null) return SetpointSource.manual;

  final active = findActiveEvent(schedule, now);
  if (active == null) return SetpointSource.manual;

  // Range events don't have a single setpoint to compare against; treat
  // them as manual unless the device's effective target falls between the
  // bounds — but that's already what happens in heat-cool mode anyway.
  // For v1, only HEAT/COOL single-setpoint events can match.
  final scheduled = active.targetTemp;
  if (scheduled == null) return SetpointSource.manual;

  final diff = (device.targetTemperature - scheduled).abs();
  return diff <= _matchEpsilonC
      ? SetpointSource.scheduled
      : SetpointSource.manual;
}
