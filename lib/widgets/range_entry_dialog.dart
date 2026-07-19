import 'package:flutter/material.dart';

import 'temp_entry_dialog.dart';

/// Result of the [RangeEntryDialog]: the confirmed heat (low) and cool (high)
/// setpoints in Celsius, guaranteed to satisfy the deadband (the dialog can't
/// confirm otherwise).
class RangeEntryResult {
  final double lowC;
  final double highC;

  const RangeEntryResult({required this.lowC, required this.highC});
}

/// Dual-field keyboard-entry dialog for the Home dial's heat-cool range
/// (Issue #116). Two integer, unit-aware fields (Heat + Cool) that reuse
/// [TempEntryDialog]'s parse/clamp/°C-°F logic per field. Presentation-only:
/// every string and tunable is passed in, so it carries no localization or
/// screen-specific coupling.
///
/// The deadband is enforced **in the form** — the confirm action is disabled
/// with an inline error until `heat + [deadbandCelsius] ≤ cool`, mirroring the
/// eco-sheet's `low < high` gate. On confirm both bounds are returned together
/// via `Navigator.pop`; Cancel (or any invalid state that survives to pop)
/// returns `null`, leaving the caller's values unchanged.
class RangeEntryDialog extends StatefulWidget {
  /// Current heat (low) and cool (high) setpoints in Celsius, used to prefill.
  final double lowC;
  final double highC;

  /// Display unit: `'C'` (case-insensitive) shows Celsius, anything else °F.
  final String scale;

  /// Accents for the heat field and cool field respectively.
  final Color heatAccent;
  final Color coolAccent;

  /// Numeral face for the entry fields.
  final TextStyle? numeralStyle;

  /// Clamp bounds and the enforced deadband, all in Celsius.
  final double minCelsius;
  final double maxCelsius;
  final double deadbandCelsius;

  /// Dialog title, field labels, action labels, and the inline deadband error —
  /// supplied by the caller (already formatted) so the dialog stays
  /// localization-agnostic.
  final String title;
  final String heatLabel;
  final String coolLabel;
  final String confirmLabel;
  final String cancelLabel;
  final String deadbandError;

  const RangeEntryDialog({
    super.key,
    required this.lowC,
    required this.highC,
    required this.scale,
    required this.heatAccent,
    required this.coolAccent,
    required this.numeralStyle,
    required this.title,
    required this.heatLabel,
    required this.coolLabel,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.deadbandError,
    this.minCelsius = 4.5,
    this.maxCelsius = 32.0,
    this.deadbandCelsius = 1.5,
  });

  @override
  State<RangeEntryDialog> createState() => _RangeEntryDialogState();
}

class _RangeEntryDialogState extends State<RangeEntryDialog> {
  static const _heatFieldKey = ValueKey('range-entry-heat-field');
  static const _coolFieldKey = ValueKey('range-entry-cool-field');
  static const _confirmKey = ValueKey('range-entry-confirm');

  late final bool _isF = widget.scale.toUpperCase() != 'C';

  late final TextEditingController _heatController = TextEditingController(
    text: TempEntryDialog.prefillText(
      widget.lowC,
      isF: _isF,
      allowDecimal: false,
    ),
  );
  late final TextEditingController _coolController = TextEditingController(
    text: TempEntryDialog.prefillText(
      widget.highC,
      isF: _isF,
      allowDecimal: false,
    ),
  );

  @override
  void dispose() {
    _heatController.dispose();
    _coolController.dispose();
    super.dispose();
  }

  /// Parse a field's text to a clamped Celsius value (integer-only), or null.
  double? _parse(TextEditingController controller) =>
      TempEntryDialog.tryParseCelsius(
        controller.text,
        isF: _isF,
        allowDecimal: false,
        minCelsius: widget.minCelsius,
        maxCelsius: widget.maxCelsius,
      );

  /// True once both bounds parse and the deadband is satisfied. The epsilon
  /// absorbs the float error from the °F→°C round-trip so an exactly-on-the-gap
  /// pair still saves.
  bool _deadbandSatisfied(double? low, double? high) =>
      low != null &&
      high != null &&
      high - low >= widget.deadbandCelsius - 1e-6;

  void _confirm() {
    final low = _parse(_heatController);
    final high = _parse(_coolController);
    // The button is disabled unless this holds, but guard anyway so a stray
    // programmatic call can't pop an invalid pair.
    if (low == null || high == null || !_deadbandSatisfied(low, high)) return;
    Navigator.of(context).pop(RangeEntryResult(lowC: low, highC: high));
  }

  Widget _field({
    required Key fieldKey,
    required TextEditingController controller,
    required String label,
    required Color accent,
    required bool autofocus,
  }) {
    final unit = _isF ? '°F' : '°C';
    return TextField(
      key: fieldKey,
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      textAlign: TextAlign.center,
      cursorColor: accent,
      style: (Theme.of(context).textTheme.headlineMedium ?? const TextStyle())
          .merge(widget.numeralStyle),
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit,
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: accent, width: 2),
        ),
      ),
      // Re-validate the deadband gate on every keystroke.
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _confirm(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Parse each field once; derive the gate and the error from those values.
    final low = _parse(_heatController);
    final high = _parse(_coolController);
    final canSave = _deadbandSatisfied(low, high);
    // Show the inline error only once both fields parse but the gap is too
    // small — an incomplete field just leaves confirm disabled without shouting.
    final showError = low != null && high != null && !canSave;

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(
            fieldKey: _heatFieldKey,
            controller: _heatController,
            label: widget.heatLabel,
            accent: widget.heatAccent,
            autofocus: true,
          ),
          const SizedBox(height: 16),
          _field(
            fieldKey: _coolFieldKey,
            controller: _coolController,
            label: widget.coolLabel,
            accent: widget.coolAccent,
            autofocus: false,
          ),
          const SizedBox(height: 12),
          if (showError)
            Text(
              widget.deadbandError,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: widget.coolAccent),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        TextButton(
          key: _confirmKey,
          style: TextButton.styleFrom(foregroundColor: widget.coolAccent),
          onPressed: canSave ? _confirm : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
