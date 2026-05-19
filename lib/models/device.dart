enum DeviceMode {
  off,
  heat,
  cool,
  heatCool,
  emergency;

  static DeviceMode fromApi(String value) => switch (value) {
    'off' => off,
    'heat' => heat,
    'cool' => cool,
    'heat-cool' => heatCool,
    'emergency' => emergency,
    _ => throw FormatException('Unknown device mode: $value'),
  };

  String toApi() => switch (this) {
    off => 'off',
    heat => 'heat',
    cool => 'cool',
    heatCool => 'heat-cool',
    emergency => 'emergency',
  };
}

class HvacState {
  final bool heater;
  final bool heatX2;
  final bool heatX3;
  final bool ac;
  final bool coolX2;
  final bool coolX3;
  final bool fan;
  final bool auxHeat;
  final bool emerHeat;
  final bool altHeat;
  final bool humidifier;
  final bool dehumidifier;
  final bool autoDehum;
  final bool fanCooling;

  const HvacState({
    required this.heater,
    required this.heatX2,
    required this.heatX3,
    required this.ac,
    required this.coolX2,
    required this.coolX3,
    required this.fan,
    required this.auxHeat,
    required this.emerHeat,
    required this.altHeat,
    required this.humidifier,
    required this.dehumidifier,
    required this.autoDehum,
    required this.fanCooling,
  });

  factory HvacState.fromJson(Map<String, dynamic> json) => HvacState(
    heater: json['heater'] as bool,
    heatX2: json['heat_x2'] as bool,
    heatX3: json['heat_x3'] as bool,
    ac: json['ac'] as bool,
    coolX2: json['cool_x2'] as bool,
    coolX3: json['cool_x3'] as bool,
    fan: json['fan'] as bool,
    auxHeat: json['aux_heat'] as bool,
    emerHeat: json['emer_heat'] as bool,
    altHeat: json['alt_heat'] as bool,
    humidifier: json['humidifier'] as bool,
    dehumidifier: json['dehumidifier'] as bool,
    autoDehum: json['auto_dehum'] as bool,
    fanCooling: json['fan_cooling'] as bool,
  );
}

class Capabilities {
  final bool canHeat;
  final bool canCool;
  final bool hasFan;
  final bool hasEmerHeat;
  final bool hasHumidifier;
  final bool hasDehumidifier;

  const Capabilities({
    required this.canHeat,
    required this.canCool,
    required this.hasFan,
    required this.hasEmerHeat,
    required this.hasHumidifier,
    required this.hasDehumidifier,
  });

  factory Capabilities.fromJson(Map<String, dynamic> json) => Capabilities(
    canHeat: json['can_heat'] as bool,
    canCool: json['can_cool'] as bool,
    hasFan: json['has_fan'] as bool,
    hasEmerHeat: json['has_emer_heat'] as bool,
    hasHumidifier: json['has_humidifier'] as bool,
    hasDehumidifier: json['has_dehumidifier'] as bool,
  );
}

class EcoTemperatures {
  final double high;
  final double low;

  const EcoTemperatures({required this.high, required this.low});

  factory EcoTemperatures.fromJson(Map<String, dynamic> json) =>
      EcoTemperatures(
        high: (json['high'] as num).toDouble(),
        low: (json['low'] as num).toDouble(),
      );
}

class Device {
  final String serial;
  final String apiKey;
  final String? name;
  final bool isAvailable;
  final bool isOnline;
  final DateTime lastSeen;
  final double currentTemperature;
  final double targetTemperature;
  final double? targetTemperatureHigh;
  final double? targetTemperatureLow;
  final int humidity;
  final double targetHumidity;
  final bool targetHumidityEnabled;
  final DeviceMode mode;
  final HvacState hvac;
  final bool fanTimerActive;
  final int fanTimerTimeout;
  final EcoTemperatures? ecoTemperatures;
  final bool hasLeaf;
  final String softwareVersion;
  final String temperatureScale;
  final Capabilities capabilities;
  final String? ecoMode;
  final int timeToTarget;
  final bool away;
  final String? scheduleMode;
  final String? structureId;
  final double backplateTemperature;
  final int subscriptionCount;

  const Device({
    required this.serial,
    required this.apiKey,
    required this.name,
    required this.isAvailable,
    required this.isOnline,
    required this.lastSeen,
    required this.currentTemperature,
    required this.targetTemperature,
    required this.targetTemperatureHigh,
    required this.targetTemperatureLow,
    required this.humidity,
    required this.targetHumidity,
    required this.targetHumidityEnabled,
    required this.mode,
    required this.hvac,
    required this.fanTimerActive,
    required this.fanTimerTimeout,
    required this.ecoTemperatures,
    required this.hasLeaf,
    required this.softwareVersion,
    required this.temperatureScale,
    required this.capabilities,
    required this.ecoMode,
    required this.timeToTarget,
    required this.away,
    required this.scheduleMode,
    required this.structureId,
    required this.backplateTemperature,
    required this.subscriptionCount,
  });

  factory Device.fromJson(Map<String, dynamic> json) => Device(
    serial: json['serial'] as String,
    apiKey: json['api_key'] as String,
    name: json['name'] as String?,
    isAvailable: json['is_available'] as bool,
    isOnline: json['is_online'] as bool,
    lastSeen: DateTime.parse(json['last_seen'] as String),
    currentTemperature: (json['current_temperature'] as num).toDouble(),
    targetTemperature: (json['target_temperature'] as num).toDouble(),
    targetTemperatureHigh: (json['target_temperature_high'] as num?)
        ?.toDouble(),
    targetTemperatureLow: (json['target_temperature_low'] as num?)?.toDouble(),
    humidity: json['humidity'] as int,
    targetHumidity: (json['target_humidity'] as num).toDouble(),
    targetHumidityEnabled: json['target_humidity_enabled'] as bool,
    mode: DeviceMode.fromApi(json['mode'] as String),
    hvac: HvacState.fromJson(json['hvac'] as Map<String, dynamic>),
    fanTimerActive: json['fan_timer_active'] as bool,
    fanTimerTimeout: json['fan_timer_timeout'] as int,
    ecoTemperatures: json['eco_temperatures'] == null
        ? null
        : EcoTemperatures.fromJson(
            json['eco_temperatures'] as Map<String, dynamic>,
          ),
    hasLeaf: json['has_leaf'] as bool,
    softwareVersion: json['software_version'] as String,
    temperatureScale: json['temperature_scale'] as String,
    capabilities: Capabilities.fromJson(
      json['capabilities'] as Map<String, dynamic>,
    ),
    ecoMode: json['eco_mode'] as String?,
    timeToTarget: json['time_to_target'] as int,
    away: json['away'] as bool,
    scheduleMode: json['schedule_mode'] as String?,
    structureId: json['structure_id'] as String?,
    backplateTemperature: (json['backplate_temperature'] as num).toDouble(),
    subscriptionCount: json['subscription_count'] as int,
  );
}
