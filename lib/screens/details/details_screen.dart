import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/device.dart';
import '../../services/device_display_name.dart';
import '../../services/mac_formatter.dart';
import '../../services/setpoint_source.dart';
import '../../settings/numeral_font.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../widgets/mode_pills.dart';
import '../../widgets/temperature_dial.dart';

/// Read-only Details screen per `docs/PRD.md` §5.3 + `docs/DESIGN.md` §9.5.
///
/// Renders three sections:
/// - **Stats grid**: humidity (with comfort label) and current setpoint (with
///   derived source — Away / Scheduled / Manual).
/// - **System info**: connection status, server URL, NLE firmware version,
///   local IP + MAC address (only when the server reports them), last sync
///   time (relative; absolute on long-press).
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

  /// Per-device display-name overrides, forwarded from the shell so the
  /// "CURRENT" header can resolve the same name shown elsewhere (Home,
  /// Schedule, device picker). Empty map falls back to the server name.
  final Map<String, String> overrides;

  const DetailsScreen({
    super.key,
    required this.device,
    required this.lastSyncAt,
    this.now = DateTime.now,
    this.overrides = const {},
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
    final numeralStyle = ref.watch(numeralFontProvider).style;
    final l = AppLocalizations.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      children: [
        _SectionHeading(
          '${displayNameFor(device, overrides)} · '
          '${_modeLabel(context, device.mode)}',
        ),
        // Row 1: temperature + humidity. IntrinsicHeight so the pair share the
        // taller card's height (the temperature tile has no footer line);
        // stretch alone can't size a Row whose height is otherwise unbounded
        // inside a ListView.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatTile(
                  label: l.detailsTemperature,
                  value: _format(
                    device.currentTemperature,
                    device.temperatureScale,
                  ),
                  numeralStyle: numeralStyle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  label: l.detailsHumidity,
                  value: '${device.humidity}%',
                  sub: _comfortLabel(context, device.humidity),
                  numeralStyle: numeralStyle,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Row 2: setpoint, full width — plenty of room for a "68° – 72°" range.
        _StatTile(
          label: l.detailsSetpoint,
          value: _setpointDisplay(device),
          sub: source.label(context),
          subTooltip: l.detailsSetpointSourceTooltip,
          numeralStyle: numeralStyle,
        ),
        const SizedBox(height: 24),
        _SectionHeading(l.detailsSectionSystem),
        _InfoRow(
          label: l.detailsStatus,
          value: device.isAvailable
              ? l.detailsStatusConnected
              : l.detailsStatusOffline,
        ),
        _InfoRow(
          label: l.detailsServer,
          value: activeServer?.url ?? l.detailsLastSyncEmpty,
        ),
        _InfoRow(
          label: l.detailsFirmware,
          value: device.softwareVersion.isEmpty
              ? l.detailsLastSyncEmpty
              : device.softwareVersion,
        ),
        // Only servers running NLE-SelfHosted main newer than 2026-06-29
        // report these; hide the rows entirely (no placeholder) elsewhere.
        if (device.localIp case final String ip when ip.isNotEmpty)
          _InfoRow(label: l.detailsLocalIp, value: ip),
        if (device.macAddress case final String mac when mac.isNotEmpty)
          _InfoRow(label: l.detailsMacAddress, value: formatMacAddress(mac)),
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

  String _comfortLabel(BuildContext context, int humidity) {
    final l = AppLocalizations.of(context);
    if (humidity < 30) return l.detailsComfortDry;
    if (humidity <= 50) return l.detailsComfortComfortable;
    return l.detailsComfortHumid;
  }

  /// Current operating mode as a first-letter-capitalised word (e.g. "Heat",
  /// "Auto"). Reuses the pill labels so there are no new mode strings; those
  /// are uppercase, so we down-case all but the first letter. `emergency` has
  /// no v1 pill, so it falls back to Heat (it is a heating mode).
  String _modeLabel(BuildContext context, DeviceMode mode) {
    final pill = ModePillOption.fromDeviceMode(mode) ?? ModePillOption.heat;
    final raw = pill.label(context);
    if (raw.isEmpty) return raw;
    return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
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

  /// Optional footer line (comfort band, setpoint source). Omitted for the
  /// temperature tile, which has no derived sub-label.
  final String? sub;
  final String? subTooltip;

  /// Configured numeral face (Settings → Appearance), merged onto the value
  /// style so the big number matches the Schedule screens. Only family+weight
  /// are replaced; the base size/colour survive.
  final TextStyle numeralStyle;

  const _StatTile({
    required this.label,
    required this.value,
    required this.numeralStyle,
    this.sub,
    this.subTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final sub = this.sub;
    final subWidget = sub == null
        ? null
        : Text(
            sub,
            style: EmberTypography.bodyMedium(color: EmberColors.textSecondary),
          );
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
          // scaleDown keeps a wide value (e.g. a "68° – 72°" range) on one
          // line when three tiles share a row on narrow phones.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: EmberTypography.displayLarge()
                  .copyWith(fontSize: 36)
                  .merge(numeralStyle),
            ),
          ),
          if (subWidget != null) ...[
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
    final l = AppLocalizations.of(context);
    final relative = lastSyncAt == null
        ? l.detailsLastSyncEmpty
        : _formatRelative(context, now().difference(lastSyncAt!));
    final absolute = lastSyncAt == null
        ? l.detailsLastSyncNoPoll
        : lastSyncAt!.toLocal().toString();

    return _InfoRow(
      label: l.detailsLastSync,
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

  String _formatRelative(BuildContext context, Duration d) {
    final l = AppLocalizations.of(context);
    if (d.inSeconds < 5) return l.detailsLastSyncJustNow;
    if (d.inSeconds < 60) return l.detailsLastSyncSeconds(d.inSeconds);
    if (d.inMinutes < 60) {
      final m = d.inMinutes;
      return m == 1 ? l.detailsLastSyncOneMinute : l.detailsLastSyncMinutes(m);
    }
    if (d.inHours < 24) {
      final h = d.inHours;
      return h == 1 ? l.detailsLastSyncOneHour : l.detailsLastSyncHours(h);
    }
    final days = d.inDays;
    return days == 1 ? l.detailsLastSyncOneDay : l.detailsLastSyncDays(days);
  }
}
