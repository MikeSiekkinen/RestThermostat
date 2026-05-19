import 'package:flutter/material.dart';

import '../../models/device.dart';
import '../../widgets/interactive_away_chip.dart';
import '../../widgets/interactive_fan_widget.dart';
import '../../widgets/interactive_mode_pills.dart';
import '../../widgets/interactive_temperature_dial.dart';
import '../../widgets/status_row.dart';
import '../../widgets/temperature_dial.dart';

/// The Home tab's body — extracted from the previous monolithic `_Home`
/// so [MainShell] can swap it into the bottom-nav `IndexedStack`.
///
/// Presentation-only: receives the resolved [device] + display-name
/// overrides; doesn't watch any provider itself.
class HomeBody extends StatelessWidget {
  final Device device;
  final Map<String, String> overrides;

  const HomeBody({super.key, required this.device, required this.overrides});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                StatusRow(device: device, nameOverrides: overrides),
                InteractiveAwayChip(device: device),
                const SizedBox(height: 8),
                // Cap the dial at the §10.3 ~240dp diameter, but let it
                // shrink on narrower viewports rather than overflowing.
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: TemperatureDial.preferredDiameter,
                    maxHeight: TemperatureDial.preferredDiameter,
                  ),
                  child: InteractiveTemperatureDial(
                    device: device,
                    displayUnit: device.temperatureScale,
                  ),
                ),
                const SizedBox(height: 24),
                InteractiveModePills(device: device),
              ],
            ),
          ),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: InteractiveFanWidget(device: device),
        ),
      ],
    );
  }
}
