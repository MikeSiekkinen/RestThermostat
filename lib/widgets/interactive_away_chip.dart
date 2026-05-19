import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../services/nle_error.dart';
import '../state/auth_failure_coordinator.dart';
import '../state/providers.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

/// Default eco temperatures used to seed the sheet when the device has no
/// `eco_temperatures` set yet. Mid-range Celsius values; the picker is
/// clamped to NLE's `[4.5, 32]` setpoint range.
const _defaultEcoLowC = 15.5;
const _defaultEcoHighC = 29.5;

/// Tappable "AWAY" chip per `docs/DESIGN.md` §9.4.
///
/// Renders nothing when the device is not currently away (`isAway = false`).
/// When away, renders a small text-only chip in Ember-green; the chip is
/// padded out to a 48dp touch target via [Material] + [InkWell].
///
/// Tap toggles away: light haptic, optimistic state flip, POST `set_away`,
/// reconciliation via [DeviceStateSource.refresh]. Failure reverts +
/// surfaces a snackbar.
///
/// Long-press shows an Ember-themed bottom sheet for editing eco
/// temperatures. Saving the sheet POSTs `set_eco_temperatures` with
/// `{"low": <C>, "high": <C>}`.
///
/// **Wire-shape note:** the device "away" state is read from
/// [Device.isAway] (which checks `eco_mode == "manual-eco"`), NOT the
/// `device.away` field — see the model getter's doc-comment for the live-
/// server divergence captured 2026-05-19.
class InteractiveAwayChip extends ConsumerStatefulWidget {
  final Device device;

  /// Sheet-show override for tests. Returns the chosen `(low, high)` in
  /// Celsius, or `null` if cancelled.
  final Future<EcoTemperaturesChoice?> Function(
    BuildContext, {
    required double initialLowC,
    required double initialHighC,
  })?
  showEcoSheet;

  const InteractiveAwayChip({
    super.key,
    required this.device,
    this.showEcoSheet,
  });

  @override
  ConsumerState<InteractiveAwayChip> createState() =>
      _InteractiveAwayChipState();
}

class _InteractiveAwayChipState extends ConsumerState<InteractiveAwayChip> {
  /// Optimistic override of `isAway`. `null` means "trust the device".
  bool? _optimisticAway;

  bool get _displayedAway => _optimisticAway ?? widget.device.isAway;

  @override
  void didUpdateWidget(covariant InteractiveAwayChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_optimisticAway != null && widget.device.isAway == _optimisticAway) {
      _optimisticAway = null;
    }
  }

  Future<void> _onTap() async {
    HapticFeedback.lightImpact();
    final newAway = !_displayedAway;
    setState(() => _optimisticAway = newAway);

    final client = ref.read(nleApiClientProvider);
    try {
      await client.sendCommand(
        serial: widget.device.serial,
        command: 'set_away',
        value: newAway,
      );
    } on NleAuthError catch (_) {
      if (!mounted) return;
      ref.read(authFailureCoordinatorProvider).fire();
      setState(() => _optimisticAway = null);
      return;
    } on NleError catch (e) {
      if (!mounted) return;
      _revert(_messageFor(e, action: 'away'));
      return;
    } catch (_) {
      if (!mounted) return;
      _revert('Couldn\'t toggle away');
      return;
    }
    if (!mounted) return;
    ref.read(deviceStateSourceProvider).refresh();
  }

  Future<void> _onLongPress() async {
    HapticFeedback.mediumImpact();
    final eco = widget.device.ecoTemperatures;
    final initLow = eco?.low ?? _defaultEcoLowC;
    final initHigh = eco?.high ?? _defaultEcoHighC;
    final show = widget.showEcoSheet ?? _defaultShowEcoSheet;
    final choice = await show(
      context,
      initialLowC: initLow,
      initialHighC: initHigh,
    );
    if (choice == null || !mounted) return;
    await _commitEco(choice);
  }

  Future<EcoTemperaturesChoice?> _defaultShowEcoSheet(
    BuildContext context, {
    required double initialLowC,
    required double initialHighC,
  }) {
    return showModalBottomSheet<EcoTemperaturesChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EcoTempsSheet(
        initialLowC: initialLowC,
        initialHighC: initialHighC,
        displayUnit: widget.device.temperatureScale,
      ),
    );
  }

  Future<void> _commitEco(EcoTemperaturesChoice choice) async {
    final client = ref.read(nleApiClientProvider);
    try {
      await client.sendCommand(
        serial: widget.device.serial,
        command: 'set_eco_temperatures',
        value: {'low': choice.lowC, 'high': choice.highC},
      );
    } on NleAuthError catch (_) {
      if (!mounted) return;
      ref.read(authFailureCoordinatorProvider).fire();
      return;
    } on NleError catch (e) {
      if (!mounted) return;
      _showSnack(_messageFor(e, action: 'eco temps'));
      return;
    } catch (_) {
      if (!mounted) return;
      _showSnack('Couldn\'t save eco temperatures');
      return;
    }
    if (!mounted) return;
    ref.read(deviceStateSourceProvider).refresh();
  }

  void _revert(String message) {
    setState(() => _optimisticAway = null);
    _showSnack(message);
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  String _messageFor(NleError e, {required String action}) {
    if (e.serverMessage != null && e.serverMessage!.isNotEmpty) {
      return e.serverMessage!;
    }
    return switch (e) {
      NleClientError() => 'Server rejected $action change',
      _ => "Couldn't change $action",
    };
  }

  @override
  Widget build(BuildContext context) {
    // The chip is invisible when inactive (per §9.4 spec: "Inactive: chip not
    // shown") but the hit target stays at 48dp so a long-press in the area
    // can still toggle away on. This matches §10.5 (text-only, no icon).
    final away = _displayedAway;
    return Semantics(
      // A toggle role (`toggled: ...`) is the cleanest screen-reader mapping
      // for a binary state with a tap action and a long-press for the eco
      // temperatures menu. The full label spells out both gestures so blind
      // users discover the long-press affordance — the visible UI has no
      // analogue for it.
      label: away
          ? 'Away mode on, tap to disable. Long press to edit eco temperatures.'
          : 'Away mode off, tap to enable. Long press to edit eco temperatures.',
      toggled: away,
      button: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: 48,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _onTap,
              onLongPress: _onLongPress,
              borderRadius: BorderRadius.circular(100),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: away
                    ? Text(
                        'AWAY',
                        style: EmberTypography.labelSmall(
                          color: EmberColors.eco,
                        ),
                      )
                    : const SizedBox(width: 32),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Plain value type for the eco-temps sheet result. Celsius, validated
/// `low < high` before returning from the sheet.
class EcoTemperaturesChoice {
  final double lowC;
  final double highC;

  const EcoTemperaturesChoice({required this.lowC, required this.highC});
}

/// Ember-themed bottom sheet for editing eco temperatures.
///
/// Two sliders (low + high) over NLE's `[4.5, 32]` Celsius range. Save button
/// only enables when `low < high`. Cancel returns `null`. Save returns
/// [EcoTemperaturesChoice].
///
/// Internal state is in Celsius; display is converted via [_displayFor] when
/// `displayUnit == 'F'`.
class _EcoTempsSheet extends StatefulWidget {
  final double initialLowC;
  final double initialHighC;
  final String displayUnit;

  const _EcoTempsSheet({
    required this.initialLowC,
    required this.initialHighC,
    required this.displayUnit,
  });

  @override
  State<_EcoTempsSheet> createState() => _EcoTempsSheetState();
}

class _EcoTempsSheetState extends State<_EcoTempsSheet> {
  static const _minC = 4.5;
  static const _maxC = 32.0;

  late double _lowC = widget.initialLowC.clamp(_minC, _maxC);
  late double _highC = widget.initialHighC.clamp(_minC, _maxC);

  bool get _canSave => _lowC < _highC;

  String _displayFor(double c) {
    if (widget.displayUnit.toUpperCase() == 'F') {
      return '${(c * 9 / 5 + 32).round()}°';
    }
    return '${c.round()}°';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D12),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                height: 4,
                width: 40,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: EmberColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'ECO TEMPERATURES',
              style: EmberTypography.labelSmall(color: EmberColors.textPrimary),
            ),
            const SizedBox(height: 16),
            _SliderRow(
              label: 'LOW (HEAT)',
              valueC: _lowC,
              minC: _minC,
              maxC: _maxC,
              displayLabel: _displayFor(_lowC),
              onChanged: (v) => setState(() => _lowC = v),
              accent: EmberColors.heatGlow,
            ),
            const SizedBox(height: 16),
            _SliderRow(
              label: 'HIGH (COOL)',
              valueC: _highC,
              minC: _minC,
              maxC: _maxC,
              displayLabel: _displayFor(_highC),
              onChanged: (v) => setState(() => _highC = v),
              accent: EmberColors.coolGlow,
            ),
            const SizedBox(height: 12),
            if (!_canSave)
              Text(
                'Low must be lower than high.',
                style: EmberTypography.bodyMedium(color: EmberColors.eco),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('CANCEL', style: EmberTypography.labelSmall()),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _canSave
                      ? () => Navigator.of(
                          context,
                        ).pop(EcoTemperaturesChoice(lowC: _lowC, highC: _highC))
                      : null,
                  child: Text(
                    'SAVE',
                    style: EmberTypography.labelSmall(
                      color: _canSave
                          ? EmberColors.eco
                          : EmberColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double valueC;
  final double minC;
  final double maxC;
  final String displayLabel;
  final ValueChanged<double> onChanged;
  final Color accent;

  const _SliderRow({
    required this.label,
    required this.valueC,
    required this.minC,
    required this.maxC,
    required this.displayLabel,
    required this.onChanged,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: EmberTypography.labelSmall()),
            Text(
              displayLabel,
              style: EmberTypography.labelSmall(color: accent),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accent,
            thumbColor: accent,
            overlayColor: accent.withValues(alpha: 0.16),
            inactiveTrackColor: EmberColors.textTertiary,
          ),
          child: Slider(
            value: valueC.clamp(minC, maxC),
            min: minC,
            max: maxC,
            divisions: ((maxC - minC) * 2).round(), // 0.5°C steps
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
