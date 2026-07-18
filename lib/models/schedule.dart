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
  /// range temps as `temp-min`/`temp-max`). Every written event is an
  /// `entry_type: "setpoint"` — Gen 2 firmware ignores the entire schedule
  /// bucket when the field is absent (Issue #93 live ablation, 2026-07-18).
  /// `continuation` entries are never serialized; `fromJson` drops them.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'time': timeSeconds,
      'type': type,
      'entry_type': 'setpoint',
    };
    if (type == 'RANGE') {
      if (targetTempLow != null) json['temp-min'] = targetTempLow;
      if (targetTempHigh != null) json['temp-max'] = targetTempHigh;
    } else {
      if (targetTemp != null) json['temp'] = targetTemp;
    }
    return json;
  }

  /// Coerce this event's `type` to agree with [scheduleMode] (`HEAT`/`COOL`/
  /// `RANGE`). The device ignores a schedule whose events contradict its
  /// `schedule_mode`, so written payloads must be internally consistent.
  ///
  /// - Matching type: returned unchanged.
  /// - `HEAT` ↔ `COOL`: the single setpoint carries over.
  /// - `RANGE` → `HEAT` keeps the low bound ("at least this warm");
  ///   `RANGE` → `COOL` keeps the high bound ("at most this warm").
  /// - Single → `RANGE`: a ±1°C band around the setpoint, clamped to the
  ///   4.5–32°C bounds (DESIGN §16.5).
  ScheduleEvent conformedTo(String scheduleMode) {
    if (type == scheduleMode) return this;
    switch (scheduleMode) {
      case 'HEAT':
      case 'COOL':
        final temp = type == 'RANGE'
            ? (scheduleMode == 'HEAT' ? targetTempLow : targetTempHigh)
            : targetTemp;
        return copyWith(
          type: scheduleMode,
          targetTemp: temp,
          nullifyTargetTemp: temp == null,
          nullifyTargetTempLow: true,
          nullifyTargetTempHigh: true,
        );
      case 'RANGE':
        final base = targetTemp ?? 20.0;
        return copyWith(
          type: 'RANGE',
          nullifyTargetTemp: true,
          targetTempLow: (base - 1.0).clamp(4.5, 32.0),
          targetTempHigh: (base + 1.0).clamp(4.5, 32.0),
        );
    }
    return this;
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
  /// Tolerant of the asymmetric NLE wire shapes. The upstream docs'
  /// `set_schedule` example shows each day's value as an array of events,
  /// but the live `GET /api/schedule` READ wraps each day's events in a
  /// map keyed by string index (`{"0": event, "1": event, …}`). We accept
  /// both on read — but note WRITES must use the map shape; Gen 2 firmware
  /// ignores array-shaped buckets (see [toJson]). We also drop
  /// `entry_type: "continuation"` entries — those are server-generated
  /// carry-overs from the previous day's last setpoint, not user-authored
  /// events; they re-appear automatically server-side after a
  /// `set_schedule` write.
  factory Schedule.fromJson(Map<String, dynamic> json) {
    // NLE wire key is `ver`; accept legacy `version` for resilience.
    final version =
        (json['ver'] as num?)?.toInt() ?? (json['version'] as num?)?.toInt();
    final name = json['name'] as String?;
    // NLE wire key is `schedule_mode`; accept legacy `mode` for resilience.
    final mode = (json['schedule_mode'] ?? json['mode']) as String?;

    final raw = json['days'] as Object?;
    final events = <int, List<ScheduleEvent>>{};

    List<ScheduleEvent> parseDay(Object? value, int dayIndex) {
      final Iterable<dynamic> rawEvents;
      if (value is List) {
        rawEvents = value;
      } else if (value is Map) {
        // Live read shape: map keyed by string indexes. Sort by key
        // order to give insertion-order parsing a deterministic seed
        // before we re-sort by time.
        final keys = value.keys.toList()..sort();
        rawEvents = [for (final k in keys) value[k]];
      } else {
        return const [];
      }
      final out = <ScheduleEvent>[];
      for (final e in rawEvents) {
        if (e is! Map<String, dynamic>) continue;
        if (e['entry_type'] == 'continuation') continue;
        out.add(ScheduleEvent.fromJson(e, dayIndex: dayIndex));
      }
      out.sort((a, b) => a.minutesOfDay.compareTo(b.minutesOfDay));
      return out;
    }

    if (raw is Map) {
      for (final entry in raw.entries) {
        final dayIndex = int.parse(entry.key.toString());
        events[dayIndex] = parseDay(entry.value, dayIndex);
      }
    } else if (raw is List) {
      for (var dayIndex = 0; dayIndex < raw.length; dayIndex++) {
        events[dayIndex] = parseDay(raw[dayIndex], dayIndex);
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

  /// Serialize to the wire shape used by `POST /command set_schedule`.
  ///
  /// Gen 2 firmware silently ignores the whole bucket unless ALL of these hold
  /// (Issue #93 live ablation against the maintainer's device, 2026-07-18 —
  /// note the upstream Control API docs' array-shaped write example does NOT
  /// work):
  ///
  /// - each day's events are wrapped in a map keyed by string index
  ///   (`{"0": ev0, "1": ev1}`) in time-sorted order, all seven days present
  ///   (empty day → empty map, DESIGN §6.7);
  /// - a top-level `name` is present (preserved from the last read, else
  ///   `"Current Schedule"`);
  /// - every event carries `entry_type: "setpoint"` (see
  ///   [ScheduleEvent.toJson]).
  ///
  /// [scheduleMode] is a required, deliberate input (derived from the device's
  /// operating mode by the save path — never a silent fallback) because the
  /// device also ignores the schedule when it disagrees with the shared
  /// bucket's `schedule_mode`; callers keep the two in sync via
  /// `set_schedule_mode`.
  Map<String, dynamic> toJson({required String scheduleMode}) {
    final days = <String, Map<String, dynamic>>{};
    for (var i = 0; i < 7; i++) {
      final list = [...(events[i] ?? const <ScheduleEvent>[])]
        ..sort((a, b) => a.minutesOfDay.compareTo(b.minutesOfDay));
      days['$i'] = <String, dynamic>{
        for (var j = 0; j < list.length; j++) '$j': list[j].toJson(),
      };
    }
    return <String, dynamic>{
      'ver': version ?? 2,
      'schedule_mode': scheduleMode,
      'name': name ?? 'Current Schedule',
      'days': days,
    };
  }

  /// Return a copy whose every event agrees with [scheduleMode], coercing any
  /// stale entries (e.g. COOL events left over from before a device-mode
  /// switch) via [ScheduleEvent.conformedTo]. Days already consistent are
  /// reused as-is.
  Schedule conformedTo(String scheduleMode) {
    final next = <int, List<ScheduleEvent>>{};
    for (final entry in events.entries) {
      next[entry.key] = [
        for (final e in entry.value) e.conformedTo(scheduleMode),
      ];
    }
    return copyWith(events: next, mode: scheduleMode);
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
