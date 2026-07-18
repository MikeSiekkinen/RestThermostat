import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/device.dart';
import '../../models/schedule.dart';
import '../../services/schedule_helpers.dart';
import '../../services/setpoint_source.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import 'day_index.dart';
import 'edit_event_screen.dart';

/// Read-only schedule view for the active device per `docs/DESIGN.md` §6 and
/// PRD §5.4. Editing arrives in #18.
///
/// Locale-aware day order on the tab strip (DESIGN §15.4); internal indexing is
/// always Monday=0 (DESIGN §6.1). The active device's serial is passed in
/// because issue #16 — which would wire up an `activeSerial` provider — hasn't
/// landed yet; this is the temporary seam.
class ScheduleScreen extends ConsumerStatefulWidget {
  /// Active device serial. Used to scope the `scheduleProvider` family.
  final String serial;

  /// The device's display temperature scale, `'F'` or `'C'` (DESIGN §8.1).
  /// Schedule events on the wire are always Celsius; we convert at the UI
  /// boundary based on this flag.
  final String temperatureScale;

  /// Active device mode — drives the tab-strip underline tint per the issue
  /// spec ("mode-tinted underline").
  final DeviceMode deviceMode;

  /// The active device's capabilities — gates the mode selector on Edit Event.
  /// Defaults to a heat-only device for the backward-compatible cases where a
  /// caller doesn't have a `Device` handy (tests, mostly).
  final Capabilities capabilities;

  /// The device's shared-bucket `schedule_mode` as last read from
  /// `/api/devices` (`Device.scheduleMode`, nullable). Forwarded to Edit
  /// Event so its save path can decide whether a `set_schedule_mode` command
  /// is needed alongside `set_schedule` (Issue #93).
  final String? scheduleMode;

  /// The resolved active device — feeds `deriveSetpointSource` (its
  /// `targetTemperature` and away state) for the background tint (Issue #97).
  /// Nullable for callers without a full `Device` (tests, mostly); the tint
  /// simply stays off then.
  final Device? device;

  /// Clock injection so the tint's active-event derivation is deterministic
  /// in tests. Production callers use the [DateTime.now] default.
  final DateTime Function() now;

  const ScheduleScreen({
    super.key,
    required this.serial,
    this.temperatureScale = 'F',
    this.deviceMode = DeviceMode.heat,
    this.scheduleMode,
    this.device,
    this.now = DateTime.now,
    this.capabilities = const Capabilities(
      canHeat: true,
      canCool: false,
      hasFan: false,
      hasEmerHeat: false,
      hasHumidifier: false,
      hasDehumidifier: false,
    ),
  });

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  /// Internal day index (Mon=0..Sun=6) currently shown in the event list.
  /// Initialized to today's index in `initState`; user taps on the tab strip
  /// move this around.
  int _selectedDay = weekdayToIndex(DateTime.now().weekday);

  /// Tint color when the active scheduled event is what's driving the
  /// current setpoint (Issue #97): heat red for an active HEAT event, cool
  /// blue for COOL, `null` (default background) otherwise — manual override,
  /// away, no/failed schedule, or an active RANGE event (which
  /// `deriveSetpointSource` deliberately never matches, DESIGN §9.5).
  ///
  /// Reuses `deriveSetpointSource` unchanged so this always agrees with the
  /// Details screen's Scheduled/Manual row by construction.
  Color? _activeScheduleTint(Schedule? schedule) {
    final device = widget.device;
    if (device == null || schedule == null) return null;
    final now = widget.now();
    final source = deriveSetpointSource(
      device: device,
      schedule: schedule,
      now: now,
    );
    if (source != SetpointSource.scheduled) return null;
    return switch (findActiveEvent(schedule, now)?.type) {
      'HEAT' => EmberColors.heatGlow,
      'COOL' => EmberColors.coolGlow,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
    final order = localeDayOrder(locale);
    final labels = displayDayLabels(locale);
    final asyncSchedule = ref.watch(scheduleProvider(widget.serial));
    // A failed refetch keeps its previous data in `AsyncValue.value`, but the
    // screen shows the error view then — keep the tint in agreement with what
    // is actually visible by treating any error as "no schedule".
    final tint = _activeScheduleTint(
      asyncSchedule.hasError ? null : asyncSchedule.value,
    );
    // Mirrors EmberBackground's glow overlay (alpha 0.18 → 0.0 radial) so the
    // tint reads as the same visual vocabulary; both stops go fully
    // transparent when no tint applies so gradient-to-gradient animation
    // fades smoothly instead of snapping.
    final glow = tint ?? Colors.transparent;

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              key: const ValueKey('schedule-tint'),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.3),
                  radius: 0.9,
                  colors: [
                    glow.withValues(alpha: tint == null ? 0.0 : 0.18),
                    glow.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
        ),
        _buildScaffold(context, order, labels, asyncSchedule),
      ],
    );
  }

  Scaffold _buildScaffold(
    BuildContext context,
    List<int> order,
    List<String> labels,
    AsyncValue<Schedule?> asyncSchedule,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).scheduleTitle),
        actions: [
          IconButton(
            key: const ValueKey('add-event-button'),
            tooltip: AppLocalizations.of(context).scheduleAddEventTooltip,
            icon: const Icon(Icons.add),
            onPressed: () => _openNewEvent(asyncSchedule.value),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _DayTabStrip(
              order: order,
              labels: labels,
              selectedDay: _selectedDay,
              underlineColor: _modeTint(widget.deviceMode),
              onTap: (day) => setState(() => _selectedDay = day),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(scheduleProvider(widget.serial));
                  // Wait for the next value so RefreshIndicator can dismiss
                  // its spinner only when fresh data has arrived.
                  await ref.read(scheduleProvider(widget.serial).future);
                },
                child: asyncSchedule.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _ErrorView(error: e),
                  data: (schedule) => _DayEventList(
                    events: schedule?.eventsForDay(_selectedDay) ?? const [],
                    temperatureScale: widget.temperatureScale,
                    onTapEvent: (event) => _openEditEvent(schedule, event),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Resolve the schedule we hand to Edit Event. The screen is unreachable
  /// before the first fetch completes (the AppBar action is enabled either
  /// way), so when the user taps "+" before data arrives we synthesize a
  /// minimal empty schedule. `set_schedule` is full-replace so an empty 7-day
  /// payload is valid (DESIGN §6.7).
  Schedule _scheduleOrEmpty(Schedule? existing) {
    // No `mode` on the synthesized schedule: the written `schedule_mode` is
    // derived from the device's operating mode at save time (Issue #93), so
    // a hardcoded default here would only mislead.
    return existing ??
        const Schedule(
          events: {0: [], 1: [], 2: [], 3: [], 4: [], 5: [], 6: []},
        );
  }

  Future<void> _openNewEvent(Schedule? schedule) async {
    final result = await Navigator.of(context).push<Schedule?>(
      MaterialPageRoute(
        builder: (_) => EditEventScreen(
          serial: widget.serial,
          capabilities: widget.capabilities,
          temperatureScale: widget.temperatureScale,
          currentSchedule: _scheduleOrEmpty(schedule),
          defaultDayIndex: _selectedDay,
          deviceMode: widget.deviceMode,
          storedScheduleMode: widget.scheduleMode,
        ),
      ),
    );
    if (result != null && mounted) {
      // The optimistic write already happened in the editor; trigger a
      // re-fetch so the screen reflects the server's eventual state. Edit
      // Event's revert path also invalidates this, so this is a no-op overlap
      // on the failure path.
      ref.invalidate(scheduleProvider(widget.serial));
    }
  }

  Future<void> _openEditEvent(Schedule? schedule, ScheduleEvent event) async {
    final result = await Navigator.of(context).push<Schedule?>(
      MaterialPageRoute(
        builder: (_) => EditEventScreen(
          serial: widget.serial,
          capabilities: widget.capabilities,
          temperatureScale: widget.temperatureScale,
          currentSchedule: _scheduleOrEmpty(schedule),
          defaultDayIndex: event.dayIndex,
          deviceMode: widget.deviceMode,
          storedScheduleMode: widget.scheduleMode,
          existingEvent: event,
        ),
      ),
    );
    if (result != null && mounted) {
      ref.invalidate(scheduleProvider(widget.serial));
    }
  }
}

class _DayTabStrip extends StatelessWidget {
  final List<int> order;
  final List<String> labels;
  final int selectedDay;
  final Color underlineColor;
  final ValueChanged<int> onTap;

  const _DayTabStrip({
    required this.order,
    required this.labels,
    required this.selectedDay,
    required this.underlineColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < order.length; i++)
            Expanded(
              child: _DayTab(
                label: labels[i],
                dayIndex: order[i],
                fullName: fullDayNames[order[i]],
                isSelected: order[i] == selectedDay,
                underlineColor: underlineColor,
                onTap: () => onTap(order[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayTab extends StatelessWidget {
  final String label;
  final int dayIndex;
  final String fullName;
  final bool isSelected;
  final Color underlineColor;
  final VoidCallback onTap;

  const _DayTab({
    required this.label,
    required this.dayIndex,
    required this.fullName,
    required this.isSelected,
    required this.underlineColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? EmberColors.textPrimary
        : EmberColors.textSecondary;
    return Semantics(
      label: fullName,
      selected: isSelected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: color),
              ),
              const SizedBox(height: 6),
              Container(
                key: ValueKey('day-underline-$dayIndex'),
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isSelected ? underlineColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayEventList extends StatelessWidget {
  final List<ScheduleEvent> events;
  final String temperatureScale;
  final ValueChanged<ScheduleEvent> onTapEvent;

  const _DayEventList({
    required this.events,
    required this.temperatureScale,
    required this.onTapEvent,
  });

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      // Wrap in a ListView so RefreshIndicator still works on an empty day.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 48),
          Center(
            child: Column(
              children: [
                Text(
                  AppLocalizations.of(context).scheduleEmptyTitle,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context).scheduleEmptyHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: events.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _EventRow(
        event: events[i],
        temperatureScale: temperatureScale,
        onTap: () => onTapEvent(events[i]),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final ScheduleEvent event;
  final String temperatureScale;
  final VoidCallback onTap;

  const _EventRow({
    required this.event,
    required this.temperatureScale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tint = _tintFor(event.type);
    final mediaQuery = MediaQuery.of(context);
    final timeLabel = _formatTime(
      event.hour,
      event.minute,
      use24Hour: mediaQuery.alwaysUse24HourFormat,
    );
    final tempLabel = _formatTemp(event, temperatureScale);

    // Screen-reader announcement: one merged label combining time + temp +
    // mode so TalkBack/VoiceOver reads "Event at 6:00 AM, 68 degrees Heat,
    // tap to edit." instead of three separate `Text` nodes whose color
    // tinting carries the mode signal visually.
    final l = AppLocalizations.of(context);
    final semanticLabel = l.scheduleEventSemanticLabel(
      timeLabel,
      tempLabel,
      event.type.toLowerCase(),
    );
    final typeLabel = _typeLabel(context, event.type);

    return Semantics(
      label: semanticLabel,
      button: true,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tint.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      timeLabel,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        tempLabel,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: tint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        typeLabel,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Localized label for an event's `type` field. Heat/Cool/Range maps to the
/// AppLocalizations key set; any unrecognized value (older fixtures, future
/// types) falls through to the raw uppercase string the API returned.
String _typeLabel(BuildContext context, String type) {
  final l = AppLocalizations.of(context);
  switch (type) {
    case 'HEAT':
      return l.scheduleEventTypeHeat;
    case 'COOL':
      return l.scheduleEventTypeCool;
    case 'RANGE':
      return l.scheduleEventTypeRange;
    default:
      return type;
  }
}

/// Tab-strip underline tint for the active device's current mode. Cool gets the
/// cool glow; everything else (heat, heat-cool, off, emergency) uses the heat
/// glow as the default Ember accent.
Color _modeTint(DeviceMode mode) {
  return mode == DeviceMode.cool ? EmberColors.coolGlow : EmberColors.heatGlow;
}

/// Color tint for an event row keyed by its `type`. HEAT/COOL get their
/// Ember glow color; RANGE blends to a neutral white because both setpoints
/// are relevant.
Color _tintFor(String type) {
  switch (type) {
    case 'HEAT':
      return EmberColors.heatGlow;
    case 'COOL':
      return EmberColors.coolGlow;
    case 'RANGE':
      return EmberColors.textPrimary;
    default:
      return EmberColors.textSecondary;
  }
}

/// Display-format the event time. 12h vs 24h follows the platform setting via
/// `MediaQueryData.alwaysUse24HourFormat`.
String _formatTime(int hour, int minute, {required bool use24Hour}) {
  final mm = minute.toString().padLeft(2, '0');
  if (use24Hour) {
    final hh = hour.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
  final period = hour < 12 ? 'AM' : 'PM';
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$h12:$mm $period';
}

/// Display-format the event setpoint(s), converting from API Celsius into the
/// device's `temperature_scale` unit (DESIGN §8.1).
String _formatTemp(ScheduleEvent event, String scale) {
  if (event.type == 'RANGE') {
    final low = _convertTemp(event.targetTempLow, scale);
    final high = _convertTemp(event.targetTempHigh, scale);
    return '$low / $high';
  }
  return _convertTemp(event.targetTemp, scale);
}

String _convertTemp(double? celsius, String scale) {
  if (celsius == null) return '—';
  if (scale.toUpperCase() == 'C') {
    return '${celsius.round()}°C';
  }
  final f = celsius * 9 / 5 + 32;
  return '${f.round()}°F';
}

class _ErrorView extends StatelessWidget {
  final Object error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 48),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              AppLocalizations.of(context).scheduleLoadError(error),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      ],
    );
  }
}
