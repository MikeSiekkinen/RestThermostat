import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../models/device.dart';
import '../../models/schedule.dart';
import '../../services/nle_api_client.dart';
import '../../settings/numeral_font.dart';
import '../../settings/time_field_palette.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../../widgets/ember_time_fields.dart';
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

  /// 24-hour time as reported by [EmberTimeFields]. `null` while the
  /// corresponding field holds empty/out-of-range input, which disables Save —
  /// invalid input is never clamped or coerced (Issue #96).
  int? _hour;
  int? _minute;
  late Set<int> _selectedDays;

  bool get _timeValid => _hour != null && _minute != null;

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
    // One accent drives both the time boxes and the temp-entry dialog: the
    // event's mode tint in "match mode", plain white in "neutral" (so nothing
    // inherits the app's warm primary).
    final neutral =
        ref.watch(timeFieldPaletteProvider) == TimeFieldPalette.neutral;
    final accent = neutral ? EmberColors.textPrimary : _tintFor(_type);
    final timeColors = neutral
        ? TimeFieldColors.neutral
        : TimeFieldColors.accented(accent);
    final numeralStyle = ref.watch(numeralFontProvider).style;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: TextButton(
          // White, not the theme's warm primary. Disabled state still greys out
          // via the button's default disabled foreground.
          style: TextButton.styleFrom(foregroundColor: EmberColors.textPrimary),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l.editEventCancel, maxLines: 1, softWrap: false),
        ),
        // Wide enough that "Cancel" (and longer localized equivalents) render
        // on a single line instead of wrapping to "Cance\nl".
        leadingWidth: 100,
        title: Text(widget.isNew ? l.editEventTitleNew : l.editEventTitleEdit),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: EmberColors.textPrimary,
            ),
            onPressed: (_saving || !_timeValid) ? null : _save,
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
              accent: accent,
              numeralStyle: numeralStyle,
              targetTemp: _targetTemp,
              targetTempLow: _targetTempLow,
              targetTempHigh: _targetTempHigh,
              onTargetTemp: (c) => setState(() => _targetTemp = c),
              onTargetTempLow: (c) => setState(() => _targetTempLow = c),
              onTargetTempHigh: (c) => setState(() => _targetTempHigh = c),
            ),
            const SizedBox(height: 24),
            EmberTimeFields(
              key: const ValueKey('ember-time-fields'),
              initialHour: _hour ?? 7,
              initialMinute: _minute ?? 0,
              use24Hour: mediaQuery.alwaysUse24HourFormat,
              colors: timeColors,
              numeralStyle: numeralStyle,
              onChanged: (h, m) => setState(() {
                _hour = h;
                _minute = m;
              }),
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
                numeralStyle: numeralStyle,
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
    final hour = _hour;
    final minute = _minute;
    if (hour == null || minute == null) return null;
    switch (_type) {
      case 'HEAT':
      case 'COOL':
        final t = _targetTemp;
        if (t == null) return null;
        return ScheduleEvent(
          dayIndex: dayIndex,
          hour: hour,
          minute: minute,
          type: _type,
          targetTemp: t.clamp(_minTempC, _maxTempC),
        );
      case 'RANGE':
        final low = _targetTempLow;
        final high = _targetTempHigh;
        if (low == null || high == null) return null;
        return ScheduleEvent(
          dayIndex: dayIndex,
          hour: hour,
          minute: minute,
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

  /// Whether to render the [label] caption above the stepper. False for the
  /// single HEAT/COOL stepper, where the mode is already stated by the pill at
  /// the top of the screen — the caption would just repeat it. Stays true for
  /// RANGE, where the two stacked steppers need HEAT/COOL captions to tell the
  /// low and high setpoints apart. [label] is still supplied when hidden so the
  /// `temp-up`/`temp-down` widget keys remain stable.
  final bool showLabel;

  /// Accent for the keyboard-entry dialog (cursor, focused underline, and the
  /// Cancel/Set actions), so it honors the time-field color scheme instead of
  /// the app's warm default primary.
  final Color accent;

  /// Numeral face for the value display and the entry dialog.
  final TextStyle? numeralStyle;

  const _TempStepper({
    required this.label,
    required this.valueC,
    required this.scale,
    required this.onChanged,
    required this.accent,
    required this.numeralStyle,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showLabel) ...[
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
        ],
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
            // Tapping the value opens a keyboard entry dialog — an alternative
            // to the +/- steppers for setting a temperature directly.
            InkWell(
              key: ValueKey('temp-value-$label'),
              onTap: () => _editViaKeyboard(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: SizedBox(
                  width: 120,
                  child: Text(
                    _format(valueC, scale),
                    textAlign: TextAlign.center,
                    style:
                        (Theme.of(context).textTheme.headlineLarge ??
                                const TextStyle())
                            .merge(numeralStyle),
                  ),
                ),
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

  /// Prompt for a temperature via the keyboard as an alternative to the +/-
  /// steppers. The user types in the device's display unit; the parsed value is
  /// converted back to Celsius and clamped to [_minTempC, _maxTempC] — matching
  /// the steppers' clamp — before it reaches [onChanged]. Non-numeric or empty
  /// input leaves the value unchanged.
  Future<void> _editViaKeyboard(BuildContext context) async {
    // The dialog owns its own [TextEditingController] via [_TempEntryDialog] so
    // that the controller is disposed in that widget's own `State.dispose()` —
    // after its `EditableText` subtree has unmounted — rather than
    // synchronously after `await showDialog`, which would race the route
    // teardown and trip `_dependents.isEmpty` (Issue #111).
    final celsius = await showDialog<double>(
      context: context,
      builder: (_) => _TempEntryDialog(
        valueC: valueC,
        scale: scale,
        accent: accent,
        numeralStyle: numeralStyle,
      ),
    );
    if (celsius != null) onChanged(celsius);
  }

  /// Format a Celsius value for prefill: drop a trailing `.0` (20.0 → "20") but
  /// keep a real fraction (20.5 → "20.5").
  static String _trimC(double c) =>
      c == c.roundToDouble() ? c.round().toString() : c.toString();

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

/// Keyboard-entry dialog for a temperature, owning its own controller for its
/// full lifetime so the controller is disposed in `dispose()` (after the
/// `EditableText` subtree unmounts) rather than synchronously after the pop —
/// which raced the route teardown and threw `_dependents.isEmpty` (Issue #111).
///
/// The user types in the device's display unit; on confirm the parsed value is
/// converted back to Celsius and clamped to [_minTempC, _maxTempC] — matching
/// the steppers' clamp — and returned via `Navigator.pop`. Cancel, empty, or
/// non-numeric input pops `null`, leaving the value unchanged.
class _TempEntryDialog extends StatefulWidget {
  final double valueC;
  final String scale;
  final Color accent;
  final TextStyle? numeralStyle;

  const _TempEntryDialog({
    required this.valueC,
    required this.scale,
    required this.accent,
    required this.numeralStyle,
  });

  @override
  State<_TempEntryDialog> createState() => _TempEntryDialogState();
}

class _TempEntryDialogState extends State<_TempEntryDialog> {
  late final bool _isF = widget.scale.toUpperCase() != 'C';
  late final TextEditingController _controller = TextEditingController(
    text: _isF
        ? (widget.valueC * 9 / 5 + 32).round().toString()
        : _TempStepper._trimC(widget.valueC),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Parse the field and pop the clamped Celsius value, or `null` if the input
  /// is empty/non-numeric (leave the current value unchanged).
  void _commit() {
    final raw = double.tryParse(_controller.text.trim());
    if (raw == null) {
      Navigator.of(context).pop();
      return;
    }
    final celsius = _isF ? (raw - 32) * 5 / 9 : raw;
    Navigator.of(context).pop(celsius.clamp(_minTempC, _maxTempC).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final unit = _isF ? '°F' : '°C';
    final minD = _isF
        ? (_minTempC * 9 / 5 + 32).round().toString()
        : _TempStepper._trimC(_minTempC);
    final maxD = _isF
        ? (_maxTempC * 9 / 5 + 32).round().toString()
        : _TempStepper._trimC(_maxTempC);

    return AlertDialog(
      title: Text(l.editEventTempEntryTitle),
      content: TextField(
        key: const ValueKey('temp-entry-field'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(decimal: !_isF),
        textAlign: TextAlign.center,
        cursorColor: widget.accent,
        style: (Theme.of(context).textTheme.headlineMedium ?? const TextStyle())
            .merge(widget.numeralStyle),
        decoration: InputDecoration(
          suffixText: unit,
          helperText: '$minD–$maxD $unit',
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: widget.accent, width: 2),
          ),
        ),
        onSubmitted: (_) => _commit(),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: widget.accent),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.editEventCancel),
        ),
        TextButton(
          key: const ValueKey('temp-entry-confirm'),
          style: TextButton.styleFrom(foregroundColor: widget.accent),
          onPressed: _commit,
          child: Text(l.editEventTempEntryConfirm),
        ),
      ],
    );
  }
}

class _TempSection extends StatelessWidget {
  final String type;
  final String scale;
  final Color accent;
  final TextStyle? numeralStyle;
  final double? targetTemp;
  final double? targetTempLow;
  final double? targetTempHigh;
  final ValueChanged<double> onTargetTemp;
  final ValueChanged<double> onTargetTempLow;
  final ValueChanged<double> onTargetTempHigh;

  const _TempSection({
    required this.type,
    required this.scale,
    required this.accent,
    required this.numeralStyle,
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
            accent: accent,
            numeralStyle: numeralStyle,
            onChanged: onTargetTempLow,
          ),
          const SizedBox(height: 16),
          _TempStepper(
            label: 'COOL',
            valueC: targetTempHigh ?? 24.0,
            scale: scale,
            accent: accent,
            numeralStyle: numeralStyle,
            onChanged: onTargetTempHigh,
          ),
        ],
      );
    }
    return _TempStepper(
      label: type,
      showLabel: false,
      valueC: targetTemp ?? 20.0,
      scale: scale,
      accent: accent,
      numeralStyle: numeralStyle,
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
