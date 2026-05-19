import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/device.dart';
import '../../services/setpoint_source.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../widgets/temperature_dial.dart';

/// Read-only Details screen per `docs/PRD.md` §5.3 + `docs/DESIGN.md` §9.5.
///
/// Renders three sections:
/// - **Stats grid**: humidity (with comfort label) and current setpoint (with
///   derived source — Away / Scheduled / Manual).
/// - **System info**: connection status, server URL, NLE firmware version,
///   last sync time (relative; absolute on long-press).
///
/// Setpoint source derivation is pure: see [deriveSetpointSource]. The
/// "Source" label exposes a `(Derived)` tooltip on long-press to remind the
/// user the value is computed locally, not from a server field.
class DetailsScreen extends ConsumerWidget {
  /// The device whose details we're showing. Caller (MainShell) resolves it
  /// from the active-serial scope so this screen stays presentation-only.
  final Device device;

  /// Last successful poll timestamp from the devices snapshot, used for the
  /// "Last sync" footer. May be null if no successful poll has happened yet.
  final DateTime? lastSyncAt;

  /// `now()` injection for deterministic tests of relative-time formatting.
  final DateTime Function() now;

  const DetailsScreen({
    super.key,
    required this.device,
    required this.lastSyncAt,
    this.now = DateTime.now,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(scheduleProvider(device.serial));
    final schedule = scheduleAsync.asData?.value;
    final source = deriveSetpointSource(
      device: device,
      schedule: schedule,
      now: now(),
    );
    final activeServer = ref.watch(activeServerProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      children: [
        _SectionHeading('CURRENT'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _StatTile(
                label: 'HUMIDITY',
                value: '${device.humidity}%',
                sub: _comfortLabel(device.humidity),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _StatTile(
                label: 'SETPOINT',
                value: _setpointDisplay(device),
                sub: source.label,
                subTooltip:
                    'Source is derived locally from schedule + away state. '
                    '(Derived)',
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _SectionHeading('SYSTEM'),
        _InfoRow(
          label: 'STATUS',
          value: device.isAvailable ? 'Connected' : 'Offline',
        ),
        _InfoRow(label: 'SERVER', value: activeServer?.url ?? '—'),
        _InfoRow(
          label: 'FIRMWARE',
          value: device.softwareVersion.isEmpty ? '—' : device.softwareVersion,
        ),
        _LastSyncRow(lastSyncAt: lastSyncAt, now: now),
      ],
    );
  }

  String _setpointDisplay(Device d) {
    if (d.mode == DeviceMode.heatCool) {
      final low = d.targetTemperatureLow;
      final high = d.targetTemperatureHigh;
      if (low != null && high != null) {
        return '${_format(low, d.temperatureScale)} – '
            '${_format(high, d.temperatureScale)}';
      }
    }
    return _format(d.targetTemperature, d.temperatureScale);
  }

  String _format(double c, String unit) =>
      '${TemperatureDial.celsiusToDisplay(c, unit).round()}°';

  String _comfortLabel(int humidity) {
    if (humidity < 30) return 'Dry';
    if (humidity <= 50) return 'Comfortable';
    return 'Humid';
  }
}

class _SectionHeading extends StatelessWidget {
  final String text;
  const _SectionHeading(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: EmberTypography.labelSmall(color: EmberColors.textTertiary),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final String? subTooltip;

  const _StatTile({
    required this.label,
    required this.value,
    required this.sub,
    this.subTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final subWidget = Text(sub, style: EmberTypography.bodyMediumItalic());
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EmberColors.textPrimary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: EmberTypography.labelSmall()),
          const SizedBox(height: 8),
          Text(
            value,
            style: EmberTypography.displayLarge().copyWith(fontSize: 36),
          ),
          const SizedBox(height: 4),
          if (subTooltip != null)
            Tooltip(
              message: subTooltip!,
              triggerMode: TooltipTriggerMode.longPress,
              child: subWidget,
            )
          else
            subWidget,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;

  const _InfoRow({required this.label, required this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: EmberTypography.labelSmall()),
          ),
          Expanded(
            child:
                trailing ??
                Text(
                  value,
                  style: EmberTypography.bodyMedium(
                    color: EmberColors.textPrimary,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _LastSyncRow extends StatelessWidget {
  final DateTime? lastSyncAt;
  final DateTime Function() now;
  const _LastSyncRow({required this.lastSyncAt, required this.now});

  @override
  Widget build(BuildContext context) {
    final relative = lastSyncAt == null
        ? '—'
        : _formatRelative(now().difference(lastSyncAt!));
    final absolute = lastSyncAt == null
        ? 'No successful poll yet'
        : lastSyncAt!.toLocal().toString();

    return _InfoRow(
      label: 'LAST SYNC',
      value: relative,
      trailing: Tooltip(
        message: absolute,
        triggerMode: TooltipTriggerMode.longPress,
        child: Text(
          relative,
          style: EmberTypography.bodyMedium(color: EmberColors.textPrimary),
        ),
      ),
    );
  }

  String _formatRelative(Duration d) {
    if (d.inSeconds < 5) return 'just now';
    if (d.inSeconds < 60) return '${d.inSeconds} seconds ago';
    if (d.inMinutes < 60) {
      final m = d.inMinutes;
      return m == 1 ? '1 minute ago' : '$m minutes ago';
    }
    if (d.inHours < 24) {
      final h = d.inHours;
      return h == 1 ? '1 hour ago' : '$h hours ago';
    }
    final days = d.inDays;
    return days == 1 ? '1 day ago' : '$days days ago';
  }
}
