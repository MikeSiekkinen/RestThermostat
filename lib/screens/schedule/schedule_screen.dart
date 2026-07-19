import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/device.dart';
import '../../models/schedule.dart';
import '../../services/device_display_name.dart';
import '../../services/schedule_helpers.dart';
import '../../services/setpoint_source.dart';
import '../../settings/numeral_font.dart';
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
  /// `targetTemperature` and away state) for the in-control event highlight
  /// (Issue #97). Nullable for callers without a full `Device` (tests,
  /// mostly); the highlight simply stays off then.
  final Device? device;

  /// Clock injection so the highlight's active-event derivation is
  /// deterministic in tests. Production callers use the [DateTime.now] default.
  final DateTime Function() now;

  /// Per-device display-name overrides (DESIGN §4.4), forwarded from
  /// `MainShell` so the header can resolve which thermostat is being scheduled
  /// (Issue #100). Defaults to empty for callers without them (tests).
  final Map<String, String> overrides;

  const ScheduleScreen({
    super.key,
    required this.serial,
    this.temperatureScale = 'F',
    this.deviceMode = DeviceMode.heat,
    this.scheduleMode,
    this.device,
    this.now = DateTime.now,
    this.overrides = const {},
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
  /// Seeded to today in `initState` off the injected clock (so tests and the
  /// tint share one notion of "now"); user taps on the tab strip move it.
  late int _selectedDay;

  /// While the loaded schedule is stale for the current mode (see
  /// [_scheduleMatchesMode]), we refetch on this cadence until the device
  /// pushes the new mode's bucket. One-shot, re-armed from `build` each time a
  /// stale result comes back, and cancelled the moment a matching schedule
  /// arrives — so it stops on its own.
  Timer? _staleRetryTimer;
  int _staleRetries = 0;
  static const _maxStaleRetries = 24;
  static const _staleRetryInterval = Duration(seconds: 8);

  /// True from the moment the device's mode changes until a schedule that
  /// matches the new mode arrives. Only while this is set do we hold the
  /// spinner over a mode-mismatched (stale) schedule — outside the switch
  /// window we trust the served data, so a steady-state screen never gates.
  bool _awaitingModeSync = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = weekdayToIndex(widget.now().weekday);
  }

  @override
  void didUpdateWidget(ScheduleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Mode was switched (e.g. on Home). Our cached schedule is now for the old
    // mode; drop it so the sanity gate shows the spinner and refetch the new
    // mode's schedule. `_maxStaleRetries` resets so the fresh switch gets a
    // full retry budget.
    if (oldWidget.device?.mode != widget.device?.mode) {
      _awaitingModeSync = true;
      _staleRetries = 0;
      _cancelStaleRetry();
      ref.invalidate(scheduleProvider(widget.serial));
    }
  }

  @override
  void dispose() {
    _cancelStaleRetry();
    super.dispose();
  }

  /// True when [schedule] is the schedule the device's current [expected] wire
  /// mode should show. A stale bucket (the previous mode's, still served until
  /// the device pushes) fails this: either its top-level `schedule_mode` or one
  /// of its event `type`s will disagree. `null` expected (device off) never
  /// gates — there's no mode to check against.
  bool _scheduleMatchesMode(Schedule schedule, String? expected) {
    if (expected == null) return true;
    if (schedule.mode != null && schedule.mode != expected) return false;
    for (final event in schedule.events.values.expand((day) => day)) {
      if (event.type != expected) return false;
    }
    return true;
  }

  void _armStaleRetry() {
    if (_staleRetryTimer != null || _staleRetries >= _maxStaleRetries) return;
    _staleRetryTimer = Timer(_staleRetryInterval, () {
      _staleRetryTimer = null;
      if (!mounted) return;
      _staleRetries++;
      ref.invalidate(scheduleProvider(widget.serial));
    });
  }

  void _cancelStaleRetry() {
    _staleRetryTimer?.cancel();
    _staleRetryTimer = null;
  }

  /// The scheduled event currently driving the setpoint, whose row gets the
  /// in-control highlight (Issue #97) — or `null` when the schedule isn't in
  /// control: manual override, away, no/failed schedule, or an active RANGE
  /// event (which `deriveSetpointSource` deliberately never matches, DESIGN
  /// §9.5).
  ///
  /// Reuses `deriveSetpointSource` unchanged so the highlight always agrees
  /// with the Details screen's Scheduled/Manual row by construction: only when
  /// it reports `scheduled` do we surface the active event.
  ScheduleEvent? _activeDrivingEvent(Schedule? schedule) {
    final device = widget.device;
    if (device == null || schedule == null) return null;
    final now = widget.now();
    final source = deriveSetpointSource(
      device: device,
      schedule: schedule,
      now: now,
    );
    if (source != SetpointSource.scheduled) return null;
    return findActiveEvent(schedule, now);
  }

  /// Header title (Issue #100): the scheduled device's display name over a
  /// small current-measured / target line. Falls back to the plain "Schedule"
  /// title when no `Device` is available (test callers).
  Widget _buildHeaderTitle(BuildContext context) {
    final l = AppLocalizations.of(context);
    final device = widget.device;
    if (device == null) return Text(l.scheduleTitle);

    final name = displayNameFor(device, widget.overrides);
    final measured = _convertTemp(
      device.currentTemperature,
      widget.temperatureScale,
    );
    final target = _headerTarget(device);
    final humidity = '${device.humidity}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(
          l.scheduleHeaderTemps(measured, humidity, target),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: EmberColors.textSecondary),
          semanticsLabel: l.scheduleHeaderTempsSemantics(
            measured,
            humidity,
            target,
          ),
        ),
      ],
    );
  }

  /// The header's "Set" value. Mirrors the Details screen's `_setpointDisplay`
  /// (details_screen.dart) so the two never disagree: a heat-cool device with
  /// both bounds shows the `low – high` band (the scalar `targetTemperature`
  /// is a midpoint/sentinel on the wire in that mode); every other mode shows
  /// the single target.
  String _headerTarget(Device device) {
    if (device.mode == DeviceMode.heatCool) {
      final low = device.targetTemperatureLow;
      final high = device.targetTemperatureHigh;
      if (low != null && high != null) {
        return '${_convertTemp(low, widget.temperatureScale)} – '
            '${_convertTemp(high, widget.temperatureScale)}';
      }
    }
    return _convertTemp(device.targetTemperature, widget.temperatureScale);
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
    final order = localeDayOrder(locale);
    final labels = displayDayLabels(locale);
    final asyncSchedule = ref.watch(scheduleProvider(widget.serial));
    // A failed refetch keeps its previous data in `AsyncValue.value`, but the
    // screen shows the error view then — keep the highlight in agreement with
    // what is actually visible by treating any error as "no schedule".
    final activeEvent = _activeDrivingEvent(
      asyncSchedule.hasError ? null : asyncSchedule.value,
    );

    return Scaffold(
      appBar: AppBar(
        // Scale the two-line header's height with the text scale so a large
        // accessibility font grows the toolbar instead of clipping it.
        toolbarHeight: MediaQuery.textScalerOf(context).scale(72),
        title: _buildHeaderTitle(context),
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
                  _staleRetries = 0;
                  ref.invalidate(scheduleProvider(widget.serial));
                  // Wait for the next value so RefreshIndicator can dismiss
                  // its spinner only when fresh data has arrived.
                  await ref.read(scheduleProvider(widget.serial).future);
                },
                child: asyncSchedule.when(
                  loading: () =>
                      _ScheduleLoadingView(accent: _modeTint(widget.deviceMode)),
                  error: (e, _) => _ErrorView(error: e),
                  data: (schedule) {
                    // After a mode switch the server keeps serving the previous
                    // mode's bucket until the device pushes the new one (NLE
                    // per-mode-bucket model). While awaiting that sync, hold the
                    // spinner over any schedule that doesn't match the new mode
                    // and keep refetching — so the old mode's events never flash.
                    final expectedWireMode =
                        widget.device?.mode.scheduleWireMode;
                    final matches =
                        schedule == null ||
                        expectedWireMode == null ||
                        _scheduleMatchesMode(schedule, expectedWireMode);
                    if (_awaitingModeSync) {
                      if (matches || _staleRetries >= _maxStaleRetries) {
                        // Synced (or gave up) — stop gating and render.
                        _awaitingModeSync = false;
                        _cancelStaleRetry();
                      } else {
                        _armStaleRetry();
                        return _ScheduleLoadingView(
                          accent: _modeTint(widget.deviceMode),
                          message: AppLocalizations.of(context).scheduleSyncing,
                        );
                      }
                    }
                    return _DayEventList(
                      events: schedule?.eventsForDay(_selectedDay) ?? const [],
                      temperatureScale: widget.temperatureScale,
                      activeEvent: activeEvent,
                      numeralStyle: ref.watch(numeralFontProvider).style,
                      onTapEvent: (event) => _openEditEvent(schedule, event),
                    );
                  },
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

  /// The event currently driving the setpoint (Issue #97), or `null`. When one
  /// of this day's events equals it, that row gets the in-control highlight.
  final ScheduleEvent? activeEvent;

  /// Numeral face for the row times and temperatures.
  final TextStyle? numeralStyle;
  final ValueChanged<ScheduleEvent> onTapEvent;

  const _DayEventList({
    required this.events,
    required this.temperatureScale,
    required this.activeEvent,
    required this.numeralStyle,
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
        isActive: activeEvent != null && events[i] == activeEvent,
        numeralStyle: numeralStyle,
        onTap: () => onTapEvent(events[i]),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final ScheduleEvent event;
  final String temperatureScale;

  /// Whether this event is the one currently driving the setpoint (Issue #97).
  /// When true the row gets a full-strength type-colored border and glow so it
  /// reads as "the schedule is holding this right now" regardless of mode.
  final bool isActive;

  /// Numeral face for the time and temperature, merged onto their styles.
  final TextStyle? numeralStyle;
  final VoidCallback onTap;

  const _EventRow({
    required this.event,
    required this.temperatureScale,
    required this.isActive,
    required this.numeralStyle,
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
    // tinting carries the mode signal visually. When this is the active event
    // the highlight is purely visual, so prepend the state for non-sighted
    // users.
    final l = AppLocalizations.of(context);
    final baseLabel = l.scheduleEventSemanticLabel(
      timeLabel,
      tempLabel,
      event.type.toLowerCase(),
    );
    final semanticLabel = isActive
        ? l.scheduleActiveEventSemanticLabel(baseLabel)
        : baseLabel;
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
            // AnimatedContainer so the highlight glides on/off (300ms
            // easeInOutCubic, DESIGN §11.4) as the clock crosses into a new
            // event or a poll changes the match. Keyed by content so a moving
            // highlight animates on stable per-event elements.
            child: AnimatedContainer(
              key: ValueKey('event-row-${event.dayIndex}-${event.timeSeconds}'),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: isActive ? 0.20 : 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isActive ? tint : tint.withValues(alpha: 0.35),
                  width: isActive ? 2 : 1,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: tint.withValues(alpha: 0.45),
                          blurRadius: 16,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      timeLabel,
                      style:
                          (Theme.of(context).textTheme.headlineLarge ??
                                  const TextStyle())
                              .merge(numeralStyle),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        tempLabel,
                        style:
                            (Theme.of(context).textTheme.bodyLarge ??
                                    const TextStyle())
                                .copyWith(color: tint, fontWeight: FontWeight.w600)
                                .merge(numeralStyle),
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

/// Centered, mode-tinted loading spinner for the schedule body — shown on the
/// first load and while a post-mode-switch schedule is still syncing. Wrapped
/// in a scrollable list so pull-to-refresh keeps working underneath it.
class _ScheduleLoadingView extends StatelessWidget {
  final Color accent;
  final String? message;
  const _ScheduleLoadingView({required this.accent, this.message});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 88),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: EmberColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
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
