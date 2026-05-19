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

  /// Seconds since midnight — wire format for the `time` field on writes.
  int get timeSeconds => (hour * 60 + minute) * 60;

  /// Return a copy with the given fields replaced. Pass `nullify*` flags to
  /// explicitly set a nullable field to `null` (since the standard
  /// `field: null` argument is indistinguishable from "use existing").
  ScheduleEvent copyWith({
    int? dayIndex,
    int? hour,
    int? minute,
    String? type,
    double? targetTemp,
    double? targetTempHigh,
    double? targetTempLow,
    bool nullifyTargetTemp = false,
    bool nullifyTargetTempHigh = false,
    bool nullifyTargetTempLow = false,
  }) {
    return ScheduleEvent(
      dayIndex: dayIndex ?? this.dayIndex,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      type: type ?? this.type,
      targetTemp: nullifyTargetTemp ? null : (targetTemp ?? this.targetTemp),
      targetTempHigh: nullifyTargetTempHigh
          ? null
          : (targetTempHigh ?? this.targetTempHigh),
      targetTempLow: nullifyTargetTempLow
          ? null
          : (targetTempLow ?? this.targetTempLow),
    );
  }

  /// Serialize back to the NLE wire shape (`time` seconds, lowercase keys for
  /// range temps as `temp-min`/`temp-max`).
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'time': timeSeconds, 'type': type};
    if (type == 'RANGE') {
      if (targetTempLow != null) json['temp-min'] = targetTempLow;
      if (targetTempHigh != null) json['temp-max'] = targetTempHigh;
    } else {
      if (targetTemp != null) json['temp'] = targetTemp;
    }
    return json;
  }

  @override
  bool operator ==(Object other) {
    return other is ScheduleEvent &&
        other.dayIndex == dayIndex &&
        other.hour == hour &&
        other.minute == minute &&
        other.type == type &&
        other.targetTemp == targetTemp &&
        other.targetTempHigh == targetTempHigh &&
        other.targetTempLow == targetTempLow;
  }

  @override
  int get hashCode => Object.hash(
    dayIndex,
    hour,
    minute,
    type,
    targetTemp,
    targetTempHigh,
    targetTempLow,
  );
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
  /// Accepts the day map under `days` and falls back to a list-of-lists form
  /// for resilience against odd server responses. (Earlier code also accepted
  /// `schedule` as the day-map key, but that conflicted with the GET-schedule
  /// envelope where `schedule` wraps the entire inner object — the call site
  /// in `NleApiClient.getSchedule` now unwraps the envelope before invoking
  /// this constructor, so there's no ambiguity.)
  factory Schedule.fromJson(Map<String, dynamic> json) {
    // NLE wire key is `ver`; accept legacy `version` for resilience.
    final version =
        (json['ver'] as num?)?.toInt() ?? (json['version'] as num?)?.toInt();
    final name = json['name'] as String?;
    // NLE wire key is `schedule_mode`; accept legacy `mode` for resilience.
    final mode = (json['schedule_mode'] ?? json['mode']) as String?;

    final raw = json['days'] as Object?;
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

  /// Return a copy with [events] (and optionally any top-level field) replaced.
  Schedule copyWith({
    Map<int, List<ScheduleEvent>>? events,
    int? version,
    String? name,
    String? mode,
  }) {
    return Schedule(
      events: events ?? this.events,
      version: version ?? this.version,
      name: name ?? this.name,
      mode: mode ?? this.mode,
    );
  }

  /// Serialize back to the NLE wire shape used by `POST /command set_schedule`.
  /// Per the Control API spec the value is `{ver, schedule_mode, days}` —
  /// `version`/`name`/`mode` are NOT recognized by the server. All seven days
  /// are emitted, even empty ones (DESIGN §6.7 — empty list is a valid day).
  Map<String, dynamic> toJson() {
    final days = <String, List<Map<String, dynamic>>>{};
    for (var i = 0; i < 7; i++) {
      final list = events[i] ?? const <ScheduleEvent>[];
      days['$i'] = [for (final e in list) e.toJson()];
    }
    return <String, dynamic>{
      'ver': version ?? 2,
      'schedule_mode': mode ?? 'HEAT',
      'days': days,
    };
  }

  /// Add [event] to its `dayIndex`. Returns a new [Schedule]; sorts the
  /// day's events by `minutesOfDay` to keep the day list in time order.
  Schedule addEvent(ScheduleEvent event) {
    final next = Map<int, List<ScheduleEvent>>.from(events);
    final day = List<ScheduleEvent>.from(next[event.dayIndex] ?? const [])
      ..add(event)
      ..sort((a, b) => a.minutesOfDay.compareTo(b.minutesOfDay));
    next[event.dayIndex] = day;
    return copyWith(events: next);
  }

  /// Replace [oldEvent] with [newEvent] within its day. If [oldEvent] is not
  /// found in the schedule, the schedule is returned unchanged. Both events
  /// must share a `dayIndex`.
  Schedule replaceEvent(ScheduleEvent oldEvent, ScheduleEvent newEvent) {
    assert(
      oldEvent.dayIndex == newEvent.dayIndex,
      'replaceEvent operates within a single day per DESIGN §6.4',
    );
    final dayList = events[oldEvent.dayIndex];
    if (dayList == null) return this;
    final index = dayList.indexOf(oldEvent);
    if (index == -1) return this;
    final next = Map<int, List<ScheduleEvent>>.from(events);
    final updated = List<ScheduleEvent>.from(dayList);
    updated[index] = newEvent;
    updated.sort((a, b) => a.minutesOfDay.compareTo(b.minutesOfDay));
    next[oldEvent.dayIndex] = updated;
    return copyWith(events: next);
  }

  /// Remove [event] from its day. If not found, the schedule is returned
  /// unchanged.
  Schedule removeEvent(ScheduleEvent event) {
    final dayList = events[event.dayIndex];
    if (dayList == null) return this;
    if (!dayList.contains(event)) return this;
    final next = Map<int, List<ScheduleEvent>>.from(events);
    next[event.dayIndex] = List<ScheduleEvent>.from(dayList)..remove(event);
    return copyWith(events: next);
  }
}
