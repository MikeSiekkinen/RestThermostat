import '../models/device.dart';

/// Resolves the display name for a thermostat per DESIGN §4.4:
///
/// 1. Local override (set via Settings → per-device rename)
/// 2. Server-side `name`, when non-null and not the sentinel `"unnamed"`
/// 3. Fallback `Thermostat (XXXX)` using the last 4 chars of the serial
String displayNameFor(Device d, Map<String, String> overrides) {
  final override = overrides[d.serial];
  if (override != null && override.isNotEmpty) return override;
  final n = d.name;
  if (n != null && n.isNotEmpty && n.toLowerCase() != 'unnamed') return n;
  final serial = d.serial;
  final tail = serial.length <= 4
      ? serial
      : serial.substring(serial.length - 4);
  return 'Thermostat ($tail)';
}
