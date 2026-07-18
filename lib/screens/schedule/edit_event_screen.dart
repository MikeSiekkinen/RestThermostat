import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/device.dart';
import '../../models/schedule.dart';
import '../../services/nle_api_client.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../../widgets/ember_time_picker.dart';
import '../../widgets/repeat_days_row.dart';

/// Per `docs/DESIGN.md` §6 / PRD §5.5 (with DESIGN §18 divergences).
///
/// Two modes:
/// - **New** (`existingEvent == null`): adds an event. Repeat-days circles are
///   shown; the user can clone the same event into multiple days.
/// - **Edit** (`existingEvent != null`): replaces the existing event in just
///   its own day. Repeat-days circles are NOT shown (DESIGN §6.4) and a
///   "Delete Event" footer with confirmation is available.
///
/// Save behavior (DESIGN §6.5):
/// 1. Update the local schedule model (clone/add/replace/delete).
/// 2. Dismiss the screen optimistically.
/// 3. POST `set_schedule` with the full schedule object.
/// 4. On success — a subtle "Schedule saved" snackbar on the parent screen.
/// 5. On failure — revert: re-invalidate the `scheduleProvider` so the
///    Schedule screen re-fetches, then show a retryable error snackbar.
class EditEventScreen extends ConsumerStatefulWidget {
  final String serial;
  final Capabilities capabilities;
  final String temperatureScale;
  final Schedule currentSchedule;

  /// The device's current operating mode — the written schedule's
  /// `schedule_mode` is derived from it (Issue #93): heat/emergency → HEAT,
  /// cool → COOL, heat-cool → RANGE. `off` derives nothing; the stored mode
  /// is kept.
  final DeviceMode deviceMode;

  /// The shared bucket's `schedule_mode` as last read from `/api/devices`
  /// (`Device.scheduleMode`). When the derived mode differs from this, the
  /// save path issues `set_schedule_mode` before `set_schedule` — the device
  /// ignores a schedule whose mode disagrees with the shared bucket.
  final String? storedScheduleMode;

  /// The event being edited. `null` for "new" mode.
  final ScheduleEvent? existingEvent;

  /// The day the user was viewing on the Schedule screen — defaults the
  /// repeat-days selection in "new" mode. Ignored in edit mode (we use the
  /// event's own `dayIndex`).
  final int defaultDayIndex;

  const EditEventScreen({
    super.key,
    required this.serial,
    required this.capabilities,
    required this.temperatureScale,
    required this.currentSchedule,
    required this.defaultDayIndex,
    this.deviceMode = DeviceMode.heat,
    this.storedScheduleMode,
    this.existingEvent,
  });

  bool get isNew => existingEvent == null;

  @override
  ConsumerState<EditEventScreen> createState() => _EditEventScreenState();
}

/// 4.5°C-32°C clamp per the issue spec / DESIGN §16.5. Top-level so the
/// stepper sub-widget below can reuse them without reaching into private
/// state.
const double _minTempC = 4.5;
const double _maxTempC = 32.0;

/// Default "comfortable" setpoints used when constructing a new event.
const double _defaultHeatTempC = 20.0;
const double _defaultCoolTempC = 24.0;
const double _defaultRangeLowC = 18.0;
const double _defaultRangeHighC = 24.0;

class _EditEventScreenState extends ConsumerState<EditEventScreen> {
  late String _type;
  double? _targetTemp;
  double? _targetTempLow;
  double? _targetTempHigh;
  late int _hour;
  late int _minute;
  late Set<int> _selectedDays;

  bool _saving = false;

  /// The `schedule_mode` this save will write, resolved once. Derived from
  /// the device's operating mode; a device in `off` (nothing to derive) falls
  /// back to the stored shared-bucket mode, then to what the capabilities
  /// support. Always one of `HEAT`/`COOL`/`RANGE`.
  late final String _wireMode = _resolveWireMode();

  String _resolveWireMode() {
    final caps = widget.capabilities;
    final capable = <String>[
      if (caps.canHeat) 'HEAT',
      if (caps.canCool) 'COOL',
      if (caps.canHeat && caps.canCool) 'RANGE',
    ];
    final derived = widget.deviceMode.scheduleWireMode;
    for (final candidate in [derived, widget.storedScheduleMode]) {
      if (candidate != null && capable.contains(candidate)) return candidate;
    }
    return capable.isEmpty ? 'HEAT' : capable.first;
  }

  @override
  void initState() {
    super.initState();
    // Coerce a pre-existing event whose type predates the current schedule
    // mode (e.g. a HEAT event after the device switched to cool) so the
    // editor prefills within the allowed type — written payloads must never
    // contain an event whose type conflicts with `schedule_mode` (Issue #93).
    final existing = widget.existingEvent?.conformedTo(_wireMode);
    if (existing != null) {
      _type = existing.type;
      _targetTemp = existing.targetTemp;
      _targetTempLow = existing.targetTempLow;
      _targetTempHigh = existing.targetTempHigh;
      _hour = existing.hour;
      _minute = existing.minute;
      _selectedDays = {existing.dayIndex};
    } else {
      _type = _wireMode;
      _hour = 7;
      _minute = 0;
      _selectedDays = {widget.defaultDayIndex};
      _applyDefaultsForType();
    }
  }

  /// Set the appropriate temp slots for the active type, leaving the others
  /// null. Run whenever the user switches mode.
  void _applyDefaultsForType() {
    switch (_type) {
      case 'HEAT':
        _targetTemp = _targetTemp ?? _defaultHeatTempC;
        _targetTempLow = null;
        _targetTempHigh = null;
        break;
      case 'COOL':
        _targetTemp = _targetTemp ?? _defaultCoolTempC;
        _targetTempLow = null;
        _targetTempHigh = null;
        break;
      case 'RANGE':
        _targetTemp = null;
        _targetTempLow = _targetTempLow ?? _defaultRangeLowC;
        _targetTempHigh = _targetTempHigh ?? _defaultRangeHighC;
        break;
    }
  }

  /// Event-type options are constrained to the single type matching the
  /// derived schedule mode (Issue #93): the device ignores a schedule whose
  /// events contradict its `schedule_mode`, so a HEAT schedule takes only
  /// HEAT events, a RANGE schedule only RANGE events, etc. Capability gating
  /// is already folded into [_resolveWireMode].
  List<String> _allowedTypes() => [_wireMode];

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l.editEventCancel),
        ),
        leadingWidth: 84,
        title: Text(widget.isNew ? l.editEventTitleNew : l.editEventTitleEdit),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(l.editEventSave),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            _ModeSelector(
              allowedTypes: _allowedTypes(),
              selected: _type,
              onChanged: (t) => setState(() {
                _type = t;
                _applyDefaultsForType();
              }),
            ),
            const SizedBox(height: 24),
            _TempSection(
              type: _type,
              scale: widget.temperatureScale,
              targetTemp: _targetTemp,
              targetTempLow: _targetTempLow,
              targetTempHigh: _targetTempHigh,
              onTargetTemp: (c) => setState(() => _targetTemp = c),
              onTargetTempLow: (c) => setState(() => _targetTempLow = c),
              onTargetTempHigh: (c) => setState(() => _targetTempHigh = c),
            ),
            const SizedBox(height: 32),
            Text(
              l.editEventTimeLabel,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 12),
            EmberTimePicker(
              key: const ValueKey('ember-time-picker'),
              initialHour: _hour,
              initialMinute: _minute,
              use24Hour: mediaQuery.alwaysUse24HourFormat,
              onChanged: (h, m) {
                _hour = h;
                _minute = m;
              },
            ),
            if (widget.isNew) ...[
              const SizedBox(height: 32),
              Text(
                l.editEventRepeatLabel,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 12),
              RepeatDaysRow(
                selectedDays: _selectedDays,
                onChanged: (s) => setState(() => _selectedDays = s),
                locale: locale,
              ),
            ],
            if (!widget.isNew) ...[
              const SizedBox(height: 40),
              Center(
                child: TextButton(
                  key: const ValueKey('delete-event-button'),
                  onPressed: _saving ? null : _confirmDelete,
                  child: Text(
                    l.editEventDeleteButton,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final event = _buildEvent();
    if (event == null) return; // invalid

    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final client = ref.read(nleApiClientProvider);

    Schedule next = widget.currentSchedule;
    if (widget.isNew) {
      for (final day in _selectedDays) {
        next = next.addEvent(event.copyWith(dayIndex: day));
      }
    } else {
      next = next.replaceEvent(widget.existingEvent!, event);
    }

    await _commit(
      client: client,
      navigator: navigator,
      messenger: messenger,
      next: next,
    );
  }

  Future<void> _commit({
    required NleApiClient client,
    required NavigatorState navigator,
    required ScaffoldMessengerState? messenger,
    required Schedule next,
  }) async {
    setState(() => _saving = true);
    final l = AppLocalizations.of(context);
    // The container outlives this State — the optimistic pop below unmounts
    // us before the network calls settle, at which point `ref.*` would throw.
    final container = ProviderScope.containerOf(context);
    // Belt-and-braces: coerce any stale events (left over from before a
    // device-mode switch) so the payload can never contradict its
    // `schedule_mode` (Issue #93).
    final conformed = next.conformedTo(_wireMode);
    // Optimistic dismiss — DESIGN §6.5 #2.
    navigator.pop(conformed);
    await _pushAndReport(
      client: client,
      container: container,
      messenger: messenger,
      l: l,
      schedule: conformed,
    );
  }

  /// Run [_push] and surface the outcome. The parent screen refetches the
  /// schedule the moment the editor pops, racing the still-in-flight write
  /// (near-deterministically losing when `set_schedule_mode` goes first), so
  /// both outcomes invalidate [scheduleProvider] again once the write has
  /// settled. Retry re-enters this method so a failed retry re-surfaces the
  /// snackbar instead of dying silently.
  Future<void> _pushAndReport({
    required NleApiClient client,
    required ProviderContainer container,
    required ScaffoldMessengerState? messenger,
    required AppLocalizations l,
    required Schedule schedule,
  }) async {
    try {
      await _push(client, schedule);
      container.invalidate(scheduleProvider(widget.serial));
      // Schedule save success — medium-impact haptic per DESIGN §11.5.
      HapticFeedback.mediumImpact();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(l.editEventSavedSnack),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      // Revert: re-fetch from server so the Schedule screen reflects truth.
      container.invalidate(scheduleProvider(widget.serial));
      messenger?.showSnackBar(
        SnackBar(
          content: Text(l.editEventSaveFailedSnack),
          action: SnackBarAction(
            label: l.editEventRetryAction,
            onPressed: () => _pushAndReport(
              client: client,
              container: container,
              messenger: messenger,
              l: l,
              schedule: schedule,
            ),
          ),
        ),
      );
    }
  }

  /// Write the schedule to the device, first aligning the shared bucket's
  /// `schedule_mode` when it disagrees with the mode we're writing — the
  /// device silently ignores the schedule otherwise (Issue #93). Re-sending
  /// `set_schedule_mode` on the retry path is harmless (idempotent).
  ///
  /// The two commands are not transactional. If the mode change lands but the
  /// schedule write fails, the device would be left with a shared-bucket mode
  /// that mismatches its stored schedule — which silently disables the whole
  /// schedule — so the failure path rolls the mode back (best-effort) before
  /// rethrowing; Retry re-runs the full sequence.
  Future<void> _push(NleApiClient client, Schedule schedule) async {
    final stored = widget.storedScheduleMode;
    final syncMode = _wireMode != stored;
    if (syncMode) {
      await client.setScheduleMode(widget.serial, _wireMode);
    }
    try {
      await client.setSchedule(
        widget.serial,
        schedule,
        scheduleMode: _wireMode,
      );
    } catch (_) {
      if (syncMode && stored != null) {
        try {
          await client.setScheduleMode(widget.serial, stored);
        } catch (_) {
          // Rollback is best-effort; the original failure is what we report.
        }
      }
      rethrow;
    }
  }

  ScheduleEvent? _buildEvent() {
    final dayIndex = widget.existingEvent?.dayIndex ?? widget.defaultDayIndex;
    switch (_type) {
      case 'HEAT':
      case 'COOL':
        final t = _targetTemp;
        if (t == null) return null;
        return ScheduleEvent(
          dayIndex: dayIndex,
          hour: _hour,
          minute: _minute,
          type: _type,
          targetTemp: t.clamp(_minTempC, _maxTempC),
        );
      case 'RANGE':
        final low = _targetTempLow;
        final high = _targetTempHigh;
        if (low == null || high == null) return null;
        return ScheduleEvent(
          dayIndex: dayIndex,
          hour: _hour,
          minute: _minute,
          type: 'RANGE',
          targetTempLow: low.clamp(_minTempC, _maxTempC),
          targetTempHigh: high.clamp(_minTempC, _maxTempC),
        );
    }
    return null;
  }

  Future<void> _confirmDelete() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final client = ref.read(nleApiClientProvider);
    final l = AppLocalizations.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.editEventDeleteDialogTitle),
        content: Text(l.editEventDeleteDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.editEventCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l.editEventDeleteConfirm,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final next = widget.currentSchedule.removeEvent(widget.existingEvent!);
    await _commit(
      client: client,
      navigator: navigator,
      messenger: messenger,
      next: next,
    );
  }
}

class _ModeSelector extends StatelessWidget {
  final List<String> allowedTypes;
  final String selected;
  final ValueChanged<String> onChanged;

  const _ModeSelector({
    required this.allowedTypes,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final type in allowedTypes)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _Pill(
              label: type,
              tint: _tintFor(type),
              selected: selected == type,
              onTap: () => onChanged(type),
            ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color tint;
  final bool selected;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.tint,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          key: ValueKey('mode-pill-$label'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? tint.withValues(alpha: 0.20) : Colors.transparent,
            border: Border.all(
              color: selected ? tint : EmberColors.textTertiary,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected
                  ? EmberColors.textPrimary
                  : EmberColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Single +/- temperature stepper. For HEAT/COOL this is the only picker; for
/// RANGE the parent shows two stacked steppers (low + high).
class _TempStepper extends StatelessWidget {
  final String label;
  final double valueC;
  final String scale;
  final ValueChanged<double> onChanged;

  const _TempStepper({
    required this.label,
    required this.valueC,
    required this.scale,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key: ValueKey('temp-down-$label'),
              icon: const Icon(Icons.remove_circle_outline),
              iconSize: 32,
              onPressed: () => onChanged(_decrement(valueC, scale)),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 120,
              child: Text(
                _format(valueC, scale),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              key: ValueKey('temp-up-$label'),
              icon: const Icon(Icons.add_circle_outline),
              iconSize: 32,
              onPressed: () => onChanged(_increment(valueC, scale)),
            ),
          ],
        ),
      ],
    );
  }

  static String _format(double celsius, String scale) {
    if (scale.toUpperCase() == 'C') return '${celsius.round()}°C';
    final f = celsius * 9 / 5 + 32;
    return '${f.round()}°F';
  }

  /// Steps in 0.5°C / 1°F so the displayed value moves by exactly one unit per
  /// tap. The stored value remains Celsius.
  static double _increment(double celsius, String scale) {
    final next = scale.toUpperCase() == 'C'
        ? celsius + 0.5
        : ((celsius * 9 / 5 + 32) + 1 - 32) * 5 / 9;
    return next.clamp(_minTempC, _maxTempC);
  }

  static double _decrement(double celsius, String scale) {
    final next = scale.toUpperCase() == 'C'
        ? celsius - 0.5
        : ((celsius * 9 / 5 + 32) - 1 - 32) * 5 / 9;
    return next.clamp(_minTempC, _maxTempC);
  }
}

class _TempSection extends StatelessWidget {
  final String type;
  final String scale;
  final double? targetTemp;
  final double? targetTempLow;
  final double? targetTempHigh;
  final ValueChanged<double> onTargetTemp;
  final ValueChanged<double> onTargetTempLow;
  final ValueChanged<double> onTargetTempHigh;

  const _TempSection({
    required this.type,
    required this.scale,
    required this.targetTemp,
    required this.targetTempLow,
    required this.targetTempHigh,
    required this.onTargetTemp,
    required this.onTargetTempLow,
    required this.onTargetTempHigh,
  });

  @override
  Widget build(BuildContext context) {
    if (type == 'RANGE') {
      return Column(
        children: [
          _TempStepper(
            label: 'HEAT',
            valueC: targetTempLow ?? 18.0,
            scale: scale,
            onChanged: onTargetTempLow,
          ),
          const SizedBox(height: 16),
          _TempStepper(
            label: 'COOL',
            valueC: targetTempHigh ?? 24.0,
            scale: scale,
            onChanged: onTargetTempHigh,
          ),
        ],
      );
    }
    return _TempStepper(
      label: type,
      valueC: targetTemp ?? 20.0,
      scale: scale,
      onChanged: onTargetTemp,
    );
  }
}

/// Color tint for a setpoint type, matching the Schedule screen's row tints.
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
