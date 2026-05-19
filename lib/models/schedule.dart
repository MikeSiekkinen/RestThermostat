/// Schedule models matching the NLE `/api/devices/<serial>/schedule` payload
/// per `docs/DESIGN.md` §6 and the live API.
///
/// The wire format is keyed Monday=0..Sunday=6 (note: NOT JavaScript-standard).
/// Event times come back as seconds-from-midnight; we split that into
/// `hour`/`minute` here for ergonomic display. Temperatures are always Celsius;
/// display-unit conversion is the UI's job.
library;

/// A single setpoint event within a day's schedule.
///
/// - `dayIndex` is always 0=Mon..6=Sun (DESIGN §6.1).
/// - `type` is one of `HEAT`, `COOL`, `RANGE` (uppercase per API wire format).
/// - For `HEAT` and `COOL`, `targetTemp` is set; `targetTempHigh`/`Low` are null.
/// - For `RANGE`, `targetTempHigh` + `targetTempLow` are set; `targetTemp` is null.
class ScheduleEvent {
  final int dayIndex;
  final int hour;
  final int minute;
  final String type;
  final double? targetTemp;
  final double? targetTempHigh;
  final double? targetTempLow;

  const ScheduleEvent({
    required this.dayIndex,
    required this.hour,
    required this.minute,
    required this.type,
    this.targetTemp,
    this.targetTempHigh,
    this.targetTempLow,
  });

  /// Parse one event object from a day's event list.
  ///
  /// Accepts both `temp`/`temp-min`/`temp-max` (API wire format) and the
  /// snake/camel-case spellings, since DESIGN §6.2 hasn't fully nailed down the
  /// serialized field names. `time` is interpreted as seconds-from-midnight.
  factory ScheduleEvent.fromJson(
    Map<String, dynamic> json, {
    required int dayIndex,
  }) {
    final timeSeconds = (json['time'] as num).toInt();
    final hour = (timeSeconds ~/ 3600) % 24;
    final minute = (timeSeconds ~/ 60) % 60;
    final type = (json['type'] as String).toUpperCase();
    final temp = (json['temp'] as num?)?.toDouble();
    final tempHigh =
        (json['temp-max'] as num?)?.toDouble() ??
        (json['temp_max'] as num?)?.toDouble();
    final tempLow =
        (json['temp-min'] as num?)?.toDouble() ??
        (json['temp_min'] as num?)?.toDouble();
    return ScheduleEvent(
      dayIndex: dayIndex,
      hour: hour,
      minute: minute,
      type: type,
      targetTemp: temp,
      targetTempHigh: tempHigh,
      targetTempLow: tempLow,
    );
  }

  /// Minutes since midnight — convenient for sorting events within a day.
  int get minutesOfDay => hour * 60 + minute;
}

/// A device's weekly schedule.
///
/// `events` is keyed by `dayIndex` (0=Mon..6=Sun). Days with no events are
/// represented by an empty list, not absence from the map.
class Schedule {
  final int? version;
  final String? name;
  final String? mode;
  final Map<int, List<ScheduleEvent>> events;

  const Schedule({required this.events, this.version, this.name, this.mode});

  /// All days present, sorted ascending. Missing days are returned as empty
  /// lists so callers can render "No events scheduled" uniformly.
  List<ScheduleEvent> eventsForDay(int dayIndex) =>
      events[dayIndex] ?? const [];

  /// Parse from the NLE wire payload. The server returns events grouped by day
  /// — common shapes seen in the wild:
  ///
  /// ```json
  /// {
  ///   "version": 2,
  ///   "name": "Default",
  ///   "mode": "HEAT",
  ///   "days": {
  ///     "0": [{"time": 25200, "type": "HEAT", "temp": 20.0}, ...],
  ///     ...
  ///   }
  /// }
  /// ```
  ///
  /// We accept either `days` or `schedule` as the day-map key, and either
  /// string-int keys (`"0".."6"`) or list-of-lists form for resilience.
  factory Schedule.fromJson(Map<String, dynamic> json) {
    final version = (json['version'] as num?)?.toInt();
    final name = json['name'] as String?;
    final mode = (json['mode'] ?? json['schedule_mode']) as String?;

    final raw = (json['days'] ?? json['schedule']) as Object?;
    final events = <int, List<ScheduleEvent>>{};

    if (raw is Map) {
      for (final entry in raw.entries) {
        final dayIndex = int.parse(entry.key.toString());
        final list = (entry.value as List<dynamic>?) ?? const [];
        events[dayIndex] =
            list
                .map(
                  (e) => ScheduleEvent.fromJson(
                    e as Map<String, dynamic>,
                    dayIndex: dayIndex,
                  ),
                )
                .toList()
              ..sort((a, b) => a.minutesOfDay.compareTo(b.minutesOfDay));
      }
    } else if (raw is List) {
      for (var dayIndex = 0; dayIndex < raw.length; dayIndex++) {
        final list = (raw[dayIndex] as List<dynamic>?) ?? const [];
        events[dayIndex] =
            list
                .map(
                  (e) => ScheduleEvent.fromJson(
                    e as Map<String, dynamic>,
                    dayIndex: dayIndex,
                  ),
                )
                .toList()
              ..sort((a, b) => a.minutesOfDay.compareTo(b.minutesOfDay));
      }
    }

    return Schedule(events: events, version: version, name: name, mode: mode);
  }
}
