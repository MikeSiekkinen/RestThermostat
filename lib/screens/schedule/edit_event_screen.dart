import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  void initState() {
    super.initState();
    final existing = widget.existingEvent;
    if (existing != null) {
      _type = existing.type;
      _targetTemp = existing.targetTemp;
      _targetTempLow = existing.targetTempLow;
      _targetTempHigh = existing.targetTempHigh;
      _hour = existing.hour;
      _minute = existing.minute;
      _selectedDays = {existing.dayIndex};
    } else {
      _type = _defaultType();
      _hour = 7;
      _minute = 0;
      _selectedDays = {widget.defaultDayIndex};
      _applyDefaultsForType();
    }
  }

  String _defaultType() {
    final caps = widget.capabilities;
    if (caps.canHeat) return 'HEAT';
    if (caps.canCool) return 'COOL';
    return 'HEAT';
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

  /// Mode-selector options derived directly from the device's capabilities.
  /// Mirrors what #8 will eventually centralize: heat-only devices don't see
  /// COOL or RANGE; cool-only devices don't see HEAT or RANGE; RANGE requires
  /// both.
  List<String> _allowedTypes() {
    final caps = widget.capabilities;
    final types = <String>[];
    if (caps.canHeat) types.add('HEAT');
    if (caps.canCool) types.add('COOL');
    if (caps.canHeat && caps.canCool) types.add('RANGE');
    return types;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        leadingWidth: 84,
        title: Text(widget.isNew ? 'New Event' : 'Edit Event'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
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
            Text('Time', style: Theme.of(context).textTheme.labelLarge),
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
              Text('Repeat', style: Theme.of(context).textTheme.labelLarge),
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
                    'Delete Event',
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
    // Optimistic dismiss — DESIGN §6.5 #2.
    navigator.pop(next);
    try {
      await client.setSchedule(widget.serial, next);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Schedule saved'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (_) {
      // Revert: re-fetch from server so the Schedule screen reflects truth.
      ref.invalidate(scheduleProvider(widget.serial));
      messenger?.showSnackBar(
        SnackBar(
          content: const Text("Couldn't save schedule. Retry?"),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => client.setSchedule(widget.serial, next),
          ),
        ),
      );
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete event?'),
        content: const Text('This will remove the event from this day.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete',
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
