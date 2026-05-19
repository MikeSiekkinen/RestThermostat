import '../models/device.dart';
import '../models/devices_response.dart';

/// A single emission from [DeviceStateSource]. Wraps the parsed device list
/// with the timestamp of when the underlying JSON was fetched plus a flag
/// indicating whether the data came from the on-disk cache or a fresh poll.
class DevicesSnapshot {
  final List<Device> devices;
  final DateTime fetchedAt;
  final bool fromCache;

  const DevicesSnapshot({
    required this.devices,
    required this.fetchedAt,
    required this.fromCache,
  });

  factory DevicesSnapshot.fromResponseJson({
    required Map<String, dynamic> json,
    required DateTime fetchedAt,
    required bool fromCache,
  }) {
    return DevicesSnapshot(
      devices: DevicesResponse.fromJson(json).devices,
      fetchedAt: fetchedAt,
      fromCache: fromCache,
    );
  }
}
