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
}

/// Template configuration defining the rules, buffers, and allowed times for a class of events.
class EventType {
  final String id;
  final String name;
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
}
