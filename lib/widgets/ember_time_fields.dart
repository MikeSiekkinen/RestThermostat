import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/gen/app_localizations.dart';
import '../theme/colors.dart';

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

  const EmberTimeFields({
    super.key,
    required this.initialHour,
    required this.initialMinute,
    required this.onChanged,
    this.use24Hour = false,
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
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  static int _to12(int hour24) {
    final h = hour24 % 12;
    return h == 0 ? 12 : h;
  }

  /// Parsed 24-hour hour, or `null` when the field is empty/out of range.
  int? get _hour24 {
    final parsed = int.tryParse(_hourCtrl.text.trim());
    if (parsed == null) return null;
    if (widget.use24Hour) {
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
        for (final error in [hourError, minuteError])
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
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
    return SizedBox(
      width: 88,
      child: TextField(
        key: key,
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(2),
        ],
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: EmberColors.textPrimary,
        ),
        decoration: InputDecoration(
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          enabledBorder: hasError
              ? UnderlineInputBorder(borderSide: BorderSide(color: errorColor))
              : null,
          focusedBorder: hasError
              ? UnderlineInputBorder(
                  borderSide: BorderSide(color: errorColor, width: 2),
                )
              : null,
        ),
        onChanged: (_) => _emit(),
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
