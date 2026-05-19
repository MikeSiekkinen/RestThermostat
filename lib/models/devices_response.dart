import 'device.dart';

class DevicesResponse {
  final List<Device> devices;
  final int total;

  const DevicesResponse({required this.devices, required this.total});

  factory DevicesResponse.fromJson(Map<String, dynamic> json) =>
      DevicesResponse(
        devices: (json['devices'] as List<dynamic>)
            .map((e) => Device.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int,
      );
}
