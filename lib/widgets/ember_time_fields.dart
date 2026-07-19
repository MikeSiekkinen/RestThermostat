import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/gen/app_localizations.dart';
import '../theme/colors.dart';

/// Resolved border/cursor colors for the time-entry boxes. Chosen upstream from
/// the `TimeFieldPalette` setting so this widget stays provider-free.
class TimeFieldColors {
  final Color restingBorder;
  final Color focusedBorder;
  final Color cursor;

  const TimeFieldColors({
    required this.restingBorder,
    required this.focusedBorder,
    required this.cursor,
  });

  /// Mode-agnostic gray with a de-warmed cursor — the default treatment.
  static const TimeFieldColors neutral = TimeFieldColors(
    restingBorder: EmberColors.textTertiary,
    focusedBorder: EmberColors.textPrimary,
    cursor: EmberColors.textSecondary,
  );

  /// Boxes tinted by [accent] (an event's mode glow): a dimmed resting outline,
  /// the full accent when focused, and an accent cursor.
  factory TimeFieldColors.accented(Color accent) => TimeFieldColors(
    restingBorder: accent.withValues(alpha: 0.55),
    focusedBorder: accent,
    cursor: accent,
  );
}

/// Hour/minute text entry per `docs/DESIGN.md` §13.6.
///
/// Two numeric text fields (hour, minute) honoring the device's 12/24-hour
/// preference. In 12-hour mode the hour field accepts 1–12 and an AM/PM
/// selector is shown; in 24-hour mode it accepts 0–23 and no selector renders.
/// Minutes accept 0–59 in both modes, leading zeros allowed.
///
/// The widget always reports a 24-hour `(hour, minute)` pair via [onChanged]
/// (12 AM → 0, 12 PM → 12). A field that is empty, non-numeric, or out of
/// range reports `null` for its slot and shows an inline error — values are
/// never clamped or coerced.
class EmberTimeFields extends StatefulWidget {
  final int initialHour;
  final int initialMinute;
  final bool use24Hour;
  final void Function(int? hour, int? minute) onChanged;

  /// Border/cursor treatment for the two boxes. Defaults to the neutral gray
  /// scheme; callers pass an accented set to tint the boxes by event mode.
  final TimeFieldColors colors;

  const EmberTimeFields({
    super.key,
    required this.initialHour,
    required this.initialMinute,
    required this.onChanged,
    this.use24Hour = false,
    this.colors = TimeFieldColors.neutral,
  });

  @override
  State<EmberTimeFields> createState() => _EmberTimeFieldsState();
}

class _EmberTimeFieldsState extends State<EmberTimeFields> {
  late final TextEditingController _hourCtrl;
  late final TextEditingController _minuteCtrl;
  late bool _isPm;

  @override
  void initState() {
    super.initState();
    final hour24 = widget.initialHour.clamp(0, 23);
    _isPm = hour24 >= 12;
    final hourText = widget.use24Hour
        ? hour24.toString().padLeft(2, '0')
        : _to12(hour24).toString();
    _hourCtrl = TextEditingController(text: hourText);
    _minuteCtrl = TextEditingController(
      text: widget.initialMinute.clamp(0, 59).toString().padLeft(2, '0'),
    );
  }

  @override
  void didUpdateWidget(EmberTimeFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `use24Hour` is fed live from `MediaQuery.alwaysUse24HourFormat`, so the
    // user can flip the system 12/24-hour setting while this screen is open.
    // Reformat the hour field for the new mode from the value it held under
    // the old one, and re-emit — otherwise the displayed digits would be
    // reinterpreted under the new mode (a 12-hour "7 PM" silently reading as
    // 07:00), desyncing the display from the value the parent saves and
    // stranding Save-gating on the stale parse.
    if (oldWidget.use24Hour != widget.use24Hour) {
      final hour24 = _parseHour24(oldWidget.use24Hour);
      if (hour24 != null) {
        _isPm = hour24 >= 12;
        _hourCtrl.text = widget.use24Hour
            ? hour24.toString().padLeft(2, '0')
            : _to12(hour24).toString();
      }
      // Defer past this build so onChanged doesn't call the parent's setState
      // mid-rebuild.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _emit();
      });
    }
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  static int _to12(int hour24) {
    final h = hour24 % 12;
    return h == 0 ? 12 : h;
  }

  /// Parsed 24-hour hour under the current [EmberTimeFields.use24Hour], or
  /// `null` when the field is empty/out of range.
  int? get _hour24 => _parseHour24(widget.use24Hour);

  /// Parse the hour field as a 24-hour value under [use24] mode, or `null`
  /// when empty/out of range. Split out so [didUpdateWidget] can read the
  /// field under the *previous* mode during a 12/24-hour flip.
  int? _parseHour24(bool use24) {
    final parsed = int.tryParse(_hourCtrl.text.trim());
    if (parsed == null) return null;
    if (use24) {
      return (parsed >= 0 && parsed <= 23) ? parsed : null;
    }
    if (parsed < 1 || parsed > 12) return null;
    if (parsed == 12) return _isPm ? 12 : 0;
    return _isPm ? parsed + 12 : parsed;
  }

  /// Parsed minute, or `null` when the field is empty/out of range.
  int? get _minute {
    final parsed = int.tryParse(_minuteCtrl.text.trim());
    if (parsed == null) return null;
    return (parsed >= 0 && parsed <= 59) ? parsed : null;
  }

  void _emit() {
    setState(() {}); // refresh inline errors
    widget.onChanged(_hour24, _minute);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hourError = _hour24 == null
        ? (widget.use24Hour ? l.editEventHourError24 : l.editEventHourError12)
        : null;
    final minuteError = _minute == null ? l.editEventMinuteError : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _field(
              context,
              key: const ValueKey('time-hour-field'),
              controller: _hourCtrl,
              label: l.editEventHourLabel,
              hasError: hourError != null,
            ),
            const _Colon(),
            _field(
              context,
              key: const ValueKey('time-minute-field'),
              controller: _minuteCtrl,
              label: l.editEventMinuteLabel,
              hasError: minuteError != null,
            ),
            if (!widget.use24Hour) ...[
              const SizedBox(width: 16),
              _AmPmToggle(
                isPm: _isPm,
                onChanged: (pm) {
                  _isPm = pm;
                  _emit();
                },
              ),
            ],
          ],
        ),
        // Errors live below the row (not per-field `errorText`) so the two
        // fields stay vertically aligned with the colon and AM/PM pills.
        // `liveRegion` restores the announcement that `InputDecoration.errorText`
        // would otherwise give screen readers when the message appears.
        for (final error in [hourError, minuteError])
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _field(
    BuildContext context, {
    required Key key,
    required TextEditingController controller,
    required String label,
    required bool hasError,
  }) {
    final errorColor = Theme.of(context).colorScheme.error;
    // Full-perimeter rounded border (replaces the old underline). Resting = a
    // subtle tertiary outline; focused = the primary accent; error = red.
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
    // Flexible + a max-width cap: the fields sit at 88px when there's room but
    // shrink rather than overflow when a large accessibility text scale grows
    // the colon and AM/PM labels past the available row width.
    return Flexible(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The label rides centered above its box (was a left-aligned
            // floating label). Excluded from semantics because the field below
            // carries the same name for screen readers.
            ExcludeSemantics(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: hasError ? errorColor : EmberColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Semantics(
              label: label,
              child: TextField(
                key: key,
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                textAlign: TextAlign.center,
                cursorColor: widget.colors.cursor,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: EmberColors.textPrimary,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 8,
                  ),
                  enabledBorder: border(
                    hasError ? errorColor : widget.colors.restingBorder,
                    hasError ? 2 : 1,
                  ),
                  focusedBorder: border(
                    hasError ? errorColor : widget.colors.focusedBorder,
                    2,
                  ),
                ),
                onChanged: (_) => _emit(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Colon extends StatelessWidget {
  const _Colon();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        ':',
        style: Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(color: EmberColors.textPrimary),
      ),
    );
  }
}

class _AmPmToggle extends StatelessWidget {
  final bool isPm;
  final ValueChanged<bool> onChanged;

  const _AmPmToggle({required this.isPm, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pill(
          context,
          key: const ValueKey('time-am-pill'),
          label: l.editEventAmLabel,
          selected: !isPm,
          onTap: () => onChanged(false),
        ),
        const SizedBox(height: 6),
        _pill(
          context,
          key: const ValueKey('time-pm-pill'),
          label: l.editEventPmLabel,
          selected: isPm,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }

  Widget _pill(
    BuildContext context, {
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        key: key,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? EmberColors.textPrimary.withValues(alpha: 0.18)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? EmberColors.textPrimary
                  : EmberColors.textTertiary,
            ),
            borderRadius: BorderRadius.circular(6),
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
