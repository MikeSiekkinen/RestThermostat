import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/device.dart';
import '../services/device_display_name.dart';
import '../services/state_derivation.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

/// Bottom sheet that lists every device in `/api/devices` order and lets the
/// user pick a new active device (DESIGN §4.2). Each row shows the resolved
/// display name (per [displayNameFor], DESIGN §4.4), the current temperature
/// rendered in the device's configured scale, and a small mode-colored dot.
///
/// The sheet does NOT persist the selection — it returns the picked serial via
/// `Navigator.pop` so the caller can update [activeDeviceSerialProvider] and
/// the on-disk `active_device_serial` in one place.
class DevicePickerSheet extends StatelessWidget {
  final List<Device> devices;
  final String? activeSerial;
  final Map<String, String> nameOverrides;

  const DevicePickerSheet({
    super.key,
    required this.devices,
    required this.activeSerial,
    this.nameOverrides = const {},
  });

  static Future<String?> show(
    BuildContext context, {
    required List<Device> devices,
    required String? activeSerial,
    Map<String, String> nameOverrides = const {},
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF111114),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DevicePickerSheet(
        devices: devices,
        activeSerial: activeSerial,
        nameOverrides: nameOverrides,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle, decorative.
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: EmberColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  AppLocalizations.of(context).devicePickerSheetHeader,
                  style: EmberTypography.labelSmall(
                    color: EmberColors.textSecondary,
                  ),
                ),
              ),
            ),
            for (final device in devices)
              _DeviceRow(
                device: device,
                selected: device.serial == activeSerial,
                nameOverrides: nameOverrides,
                onTap: () => Navigator.of(context).pop(device.serial),
              ),
          ],
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final Device device;
  final bool selected;
  final Map<String, String> nameOverrides;
  final VoidCallback onTap;

  const _DeviceRow({
    required this.device,
    required this.selected,
    required this.nameOverrides,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = displayNameFor(device, nameOverrides);
    final status = deriveStatus(device);
    final temp = _formatTemperature(device);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: status.dotColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: EmberTypography.bodyMedium(
                      color: EmberColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    temp,
                    style: EmberTypography.labelSmall(
                      color: EmberColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check, color: EmberColors.textPrimary, size: 18),
          ],
        ),
      ),
    );
  }

  String _formatTemperature(Device device) {
    final celsius = device.currentTemperature;
    if (device.temperatureScale == 'C') {
      return '${celsius.round()}°C';
    }
    final fahrenheit = celsius * 9 / 5 + 32;
    return '${fahrenheit.round()}°F';
  }
}
