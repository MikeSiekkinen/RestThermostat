import 'package:flutter/material.dart';

/// A numeric keyboard-entry dialog for a temperature, shared by the Home dial
/// and the Schedule → Edit Event screen. Presentation-only: every string and
/// tunable is passed in, so it carries no localization or screen-specific
/// coupling.
///
/// The user types in the device's display unit ([scale] `'C'`/`'F'`); on
/// confirm the value is converted back to Celsius, clamped to
/// [[minCelsius], [maxCelsius]], and returned via `Navigator.pop`. Cancel,
/// empty, or non-numeric input pops `null`, leaving the caller's value
/// unchanged.
///
/// Lifecycle note (Issue #111): the dialog owns its [TextEditingController] for
/// its full lifetime and disposes it in `State.dispose()` — after the
/// `EditableText` subtree unmounts — rather than synchronously after the pop,
/// which would race the route teardown and trip `_dependents.isEmpty`.
class TempEntryDialog extends StatefulWidget {
  /// Current value in Celsius, used to prefill the field.
  final double valueC;

  /// Display unit: `'C'` (case-insensitive) shows Celsius, anything else °F.
  final String scale;

  /// Accent for the cursor, focused underline, and the Cancel/confirm actions.
  final Color accent;

  /// Numeral face for the entry field.
  final TextStyle? numeralStyle;

  /// When false, the value is entered and committed as a whole display-unit
  /// degree (numeric keyboard advertises no decimal, and a pasted fraction is
  /// rounded). The Home dial shows whole degrees, so it passes false; the
  /// schedule editor allows a Celsius fraction and passes true for °C.
  final bool allowDecimal;

  /// Dialog title, confirm-action label, and cancel-action label — supplied by
  /// the caller so the dialog stays localization-agnostic.
  final String title;
  final String confirmLabel;
  final String cancelLabel;

  /// Clamp bounds in Celsius. Both callers use the app-wide 4.5–32.0 range.
  final double minCelsius;
  final double maxCelsius;

  const TempEntryDialog({
    super.key,
    required this.valueC,
    required this.scale,
    required this.accent,
    required this.numeralStyle,
    required this.allowDecimal,
    required this.title,
    required this.confirmLabel,
    required this.cancelLabel,
    this.minCelsius = 4.5,
    this.maxCelsius = 32.0,
  });

  /// Format a Celsius value for prefill: drop a trailing `.0` (20.0 → "20") but
  /// keep a real fraction (20.5 → "20.5").
  static String _trim(double c) =>
      c == c.roundToDouble() ? c.round().toString() : c.toString();

  /// The prefill string for a field, in the display unit. Whole degrees when
  /// [allowDecimal] is false; otherwise a trimmed fraction. Shared with
  /// [RangeEntryDialog] so both dialogs seed their fields identically.
  static String prefillText(
    double celsius, {
    required bool isF,
    required bool allowDecimal,
  }) {
    final display = isF ? celsius * 9 / 5 + 32 : celsius;
    return allowDecimal ? _trim(display) : display.round().toString();
  }

  /// Parse a field's [text] to a clamped Celsius value, or `null` if the input
  /// is empty/non-numeric. A locale-comma decimal ("20,5") is normalized so it
  /// parses, and `NaN` is rejected — `double.nan` would otherwise survive
  /// [num.clamp] as the upper limit and silently commit the ceiling. When
  /// [allowDecimal] is false the value is rounded to a whole display-unit
  /// degree first, so a pasted fraction can't produce an off-grid setpoint.
  /// Shared with [RangeEntryDialog] so both dialogs parse/clamp identically.
  static double? tryParseCelsius(
    String text, {
    required bool isF,
    required bool allowDecimal,
    required double minCelsius,
    required double maxCelsius,
  }) {
    final raw = double.tryParse(text.trim().replaceAll(',', '.'));
    if (raw == null || raw.isNaN) return null;
    final value = allowDecimal ? raw : raw.roundToDouble();
    final celsius = isF ? (value - 32) * 5 / 9 : value;
    return celsius.clamp(minCelsius, maxCelsius).toDouble();
  }

  @override
  State<TempEntryDialog> createState() => _TempEntryDialogState();
}

class _TempEntryDialogState extends State<TempEntryDialog> {
  late final bool _isF = widget.scale.toUpperCase() != 'C';

  late final TextEditingController _controller = TextEditingController(
    text: TempEntryDialog.prefillText(
      widget.valueC,
      isF: _isF,
      allowDecimal: widget.allowDecimal,
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Parse the field and pop the clamped Celsius value, or `null` if the input
  /// is empty/non-numeric (leave the current value unchanged). Delegates to the
  /// shared [TempEntryDialog.tryParseCelsius].
  void _commit() {
    final celsius = TempEntryDialog.tryParseCelsius(
      _controller.text,
      isF: _isF,
      allowDecimal: widget.allowDecimal,
      minCelsius: widget.minCelsius,
      maxCelsius: widget.maxCelsius,
    );
    Navigator.of(context).pop(celsius);
  }

  @override
  Widget build(BuildContext context) {
    final unit = _isF ? '°F' : '°C';
    final minD = _isF
        ? (widget.minCelsius * 9 / 5 + 32).round().toString()
        : TempEntryDialog._trim(widget.minCelsius);
    final maxD = _isF
        ? (widget.maxCelsius * 9 / 5 + 32).round().toString()
        : TempEntryDialog._trim(widget.maxCelsius);

    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('temp-entry-field'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(
          decimal: widget.allowDecimal,
        ),
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
          child: Text(widget.cancelLabel),
        ),
        TextButton(
          key: const ValueKey('temp-entry-confirm'),
          style: TextButton.styleFrom(foregroundColor: widget.accent),
          onPressed: _commit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
