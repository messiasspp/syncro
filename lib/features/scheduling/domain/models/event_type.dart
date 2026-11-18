import 'time_range.dart';

/// Defines how the event respects work boundaries.
enum WorkHoursConstraint {
  /// Must occur strictly within configured work hours (e.g. clinical patient visits).
  workHoursOnly,

  /// Must occur strictly outside of work hours (e.g. social events, dinners).
  outsideWorkHours,

  /// Can be scheduled at any time within allowed windows.
  bothFlexible,
}

/// How new appointments are confirmed.
enum SchedulingMode {
  /// System automatically commits the top optimal slot directly to the calendar.
  instantAuto,

  /// System presents ranked candidate slots for 1-tap user confirmation.
  suggestTopRanked,
}

/// A recurring weekly time window (e.g., "Thursdays 19:00 - 22:00").
class DayTimeWindow {
  /// 1 = Monday, 7 = Sunday (matching [DateTime.monday] ... [DateTime.sunday])
  final int dayOfWeek;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;

  const DayTimeWindow({
    required this.dayOfWeek,
    required this.startHour,
    this.startMinute = 0,
    required this.endHour,
    this.endMinute = 0,
  });

  /// Instantiates a concrete [TimeRange] for the specific [date] matching this day of week.
  TimeRange toTimeRange(DateTime date) {
    require(
      date.weekday == dayOfWeek,
      'Target date weekday (${date.weekday}) does not match window dayOfWeek ($dayOfWeek)',
    );

    return TimeRange(
      start: DateTime(date.year, date.month, date.day, startHour, startMinute),
      end: DateTime(date.year, date.month, date.day, endHour, endMinute),
    );
  }

  /// Serializes this window to a JSON-compatible map for SQLite storage.
  Map<String, dynamic> toJson() => {
        'dayOfWeek': dayOfWeek,
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
      };

  /// Reconstructs a [DayTimeWindow] from a decoded JSON map.
  factory DayTimeWindow.fromJson(Map<String, dynamic> json) {
    return DayTimeWindow(
      dayOfWeek: json['dayOfWeek'] as int,
      startHour: json['startHour'] as int,
      startMinute: (json['startMinute'] as int?) ?? 0,
      endHour: json['endHour'] as int,
      endMinute: (json['endMinute'] as int?) ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DayTimeWindow &&
          runtimeType == other.runtimeType &&
          dayOfWeek == other.dayOfWeek &&
          startHour == other.startHour &&
          startMinute == other.startMinute &&
          endHour == other.endHour &&
          endMinute == other.endMinute;

  @override
  int get hashCode =>
      Object.hash(dayOfWeek, startHour, startMinute, endHour, endMinute);
}

/// Template configuration defining the rules, buffers, and allowed times for a class of events.
class EventType {
  final String id;
  final String name;
  final String code;
  final String colorHex;
  final WorkHoursConstraint workHoursConstraint;
  final Duration minDuration;
  final Duration maxDuration;
  final Duration bufferBefore;
  final Duration bufferAfter;
  final SchedulingMode schedulingMode;
  final List<DayTimeWindow> allowedTimeWindows;
  final String? calendarMappingId;

  const EventType({
    required this.id,
    required this.name,
    this.code = '',
    this.colorHex = '#2196F3',
    this.workHoursConstraint = WorkHoursConstraint.bothFlexible,
    required this.minDuration,
    required this.maxDuration,
    this.bufferBefore = Duration.zero,
    this.bufferAfter = Duration.zero,
    this.schedulingMode = SchedulingMode.suggestTopRanked,
    this.allowedTimeWindows = const [],
    this.calendarMappingId,
  });

  /// Sanitizes a group code to uppercase ASCII letters & digits only, max 4 chars.
  static String sanitizeCode(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return cleaned.length > 4 ? cleaned.substring(0, 4) : cleaned;
  }

  /// Generates a default 2–4 character uppercase alphanumeric code from [name].
  /// E.g., "Mounjaro Clinical Study" -> "MCS", "Friends Zone" -> "FZ", "Friends" -> "FRI".
  static String generateDefaultCode(String name) {
    final words = name
        .trim()
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'GRP';
    if (words.length >= 2) {
      final initials = words.take(4).map((w) => w[0].toUpperCase()).join();
      return sanitizeCode(initials);
    }
    final single = sanitizeCode(words.first);
    if (single.isEmpty) return 'GRP';
    return single.length > 3 ? single.substring(0, 3) : single;
  }

  /// Returns the persisted sanitized code, or generates a default from [name].
  String get effectiveCode {
    final cleaned = sanitizeCode(code);
    return cleaned.isNotEmpty ? cleaned : generateDefaultCode(name);
  }

  EventType copyWith({
    String? id,
    String? name,
    String? code,
    String? colorHex,
    WorkHoursConstraint? workHoursConstraint,
    Duration? minDuration,
    Duration? maxDuration,
    Duration? bufferBefore,
    Duration? bufferAfter,
    SchedulingMode? schedulingMode,
    List<DayTimeWindow>? allowedTimeWindows,
    String? calendarMappingId,
    bool clearCalendarMappingId = false,
  }) {
    return EventType(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      colorHex: colorHex ?? this.colorHex,
      workHoursConstraint: workHoursConstraint ?? this.workHoursConstraint,
      minDuration: minDuration ?? this.minDuration,
      maxDuration: maxDuration ?? this.maxDuration,
      bufferBefore: bufferBefore ?? this.bufferBefore,
      bufferAfter: bufferAfter ?? this.bufferAfter,
      schedulingMode: schedulingMode ?? this.schedulingMode,
      allowedTimeWindows: allowedTimeWindows ?? this.allowedTimeWindows,
      calendarMappingId: clearCalendarMappingId
          ? null
          : (calendarMappingId ?? this.calendarMappingId),
    );
  }
}
