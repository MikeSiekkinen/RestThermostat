import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

/// The four HVAC-mode pill options surfaced by the home screen, per
/// `docs/PRD.md` §4.5 and `docs/DESIGN.md` §9.1.
///
/// Distinct from [DeviceMode] because the API surface includes `emergency`
/// (aux heat) which is intentionally not exposed in v1 (DESIGN §9.1). The
/// converter functions below are the only place where the display label
/// `AUTO` is mapped to the API value `heat-cool`.
enum ModePillOption {
  off,
  heat,
  cool,
  auto;

  /// Uppercase display label rendered inside the pill.
  String get label => switch (this) {
    off => 'OFF',
    heat => 'HEAT',
    cool => 'COOL',
    auto => 'AUTO',
  };

  /// Map this pill option to the underlying [DeviceMode] that a tap should
  /// translate to. Round-trips with [fromDeviceMode] for the v1 four-mode set.
  DeviceMode toDeviceMode() => switch (this) {
    off => DeviceMode.off,
    heat => DeviceMode.heat,
    cool => DeviceMode.cool,
    auto => DeviceMode.heatCool,
  };

  /// Map a device's current [DeviceMode] back to the pill option that should
  /// render as active. Returns `null` for `emergency` because that mode is not
  /// represented as a pill in v1 — when the device reports emergency, no pill
  /// is highlighted.
  static ModePillOption? fromDeviceMode(DeviceMode mode) => switch (mode) {
    DeviceMode.off => off,
    DeviceMode.heat => heat,
    DeviceMode.cool => cool,
    DeviceMode.heatCool => auto,
    DeviceMode.emergency => null,
  };
}

/// Compute the visible pill options for the supplied capability set.
///
/// Capability gating rules (DESIGN §8.2):
/// - `OFF` is always shown.
/// - `HEAT` shown only when `can_heat`.
/// - `COOL` shown only when `can_cool`.
/// - `AUTO` shown only when both `can_heat` and `can_cool` (auto needs both).
///
/// The returned list preserves OFF → HEAT → COOL → AUTO order so the layout
/// collapses left-to-right rather than padding missing-pill space.
List<ModePillOption> visiblePillsFor(Capabilities capabilities) {
  return [
    ModePillOption.off,
    if (capabilities.canHeat) ModePillOption.heat,
    if (capabilities.canCool) ModePillOption.cool,
    if (capabilities.canHeat && capabilities.canCool) ModePillOption.auto,
  ];
}

/// Read-only mode-pill row rendered below the temperature dial per
/// `docs/DESIGN.md` §10.6.
///
/// Visual contract:
/// - Pills are rounded (100dp radius), padded 12dp/8dp.
/// - Inactive pill: 1dp border `rgba(255,255,255,0.1)`, 2% white fill,
///   JetBrains Mono uppercase label in secondary-tier white.
/// - Active pill: mode-tinted 1dp border at full opacity, ~16% mode-tinted
///   fill, mode-colored label, soft outer `BoxShadow` glow.
///
/// Active-tint color per option:
/// - `OFF` and `AUTO`: neutral white (matches the §10/§11 background-and-dial
///   convention of using neutral chrome for the non-mode-specific states).
/// - `HEAT`: [EmberColors.heatGlow].
/// - `COOL`: [EmberColors.coolGlow].
///
/// `onModeTap` is accepted now but no-op'd by [_ModePill]'s gesture detector
/// in this read-only ticket — issue #12 will wire `set_mode` commands. The
/// parent is free to pass an empty callback.
class ModePills extends StatelessWidget {
  /// Current device mode. Used only to decide which pill renders as active.
  final DeviceMode currentMode;

  /// Device capabilities. Drives which pills appear (§8.2).
  final Capabilities capabilities;

  /// Tap callback. Receives the tapped pill option. The widget itself doesn't
  /// translate to API values — callers use [ModePillOption.toDeviceMode] /
  /// `DeviceMode.toApi()`.
  final ValueChanged<ModePillOption>? onModeTap;

  const ModePills({
    super.key,
    required this.currentMode,
    required this.capabilities,
    this.onModeTap,
  });

  @override
  Widget build(BuildContext context) {
    final visible = visiblePillsFor(capabilities);
    final active = ModePillOption.fromDeviceMode(currentMode);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final option in visible)
          _ModePill(
            option: option,
            isActive: option == active,
            onTap: onModeTap == null ? null : () => onModeTap!(option),
          ),
      ],
    );
  }
}

class _ModePill extends StatelessWidget {
  final ModePillOption option;
  final bool isActive;
  final VoidCallback? onTap;

  const _ModePill({
    required this.option,
    required this.isActive,
    required this.onTap,
  });

  Color _accentFor(ModePillOption option) => switch (option) {
    ModePillOption.heat => EmberColors.heatGlow,
    ModePillOption.cool => EmberColors.coolGlow,
    ModePillOption.off || ModePillOption.auto => EmberColors.textPrimary,
  };

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(option);
    final borderColor = isActive
        ? accent
        : EmberColors.textPrimary.withValues(alpha: 0.10);
    final fillColor = isActive
        ? accent.withValues(alpha: 0.16)
        : EmberColors.textPrimary.withValues(alpha: 0.02);
    final labelColor = isActive ? accent : EmberColors.textSecondary;
    final shadow = isActive
        ? [
            BoxShadow(
              color: accent.withValues(alpha: 0.35),
              blurRadius: 12,
              spreadRadius: 0,
            ),
          ]
        : const <BoxShadow>[];

    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: shadow,
      ),
      child: Text(
        option.label,
        style: EmberTypography.labelSmall(color: labelColor),
      ),
    );

    // DESIGN §14.5 + Material guidelines: tap target ≥ 48dp. The pill itself
    // stays at its natural ~32dp height so the row reads as designed; the
    // invisible ConstrainedBox + Center extends the gesture region to 48dp
    // above/below the pill without changing the visual.
    return Semantics(
      button: onTap != null,
      selected: isActive,
      label: option.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(widthFactor: 1, child: pill),
        ),
      ),
    );
  }
}
