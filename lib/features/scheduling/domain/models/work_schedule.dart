import 'time_range.dart';

/// Models the user's primary work commitments and boundary configurations.
///
/// This forms the basis for rule enforcement such as `work_hours_only`
/// (e.g. Mounjaro clinical visits) and `outside_work_hours` (e.g. Friends Zone).
class WorkSchedule {
  final Set<int> workDays;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;

  const WorkSchedule({
    this.workDays = const {
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    },
    this.startHour = 8,
    this.startMinute = 0,
    this.endHour = 18,
    this.endMinute = 0,
  });

  /// Checks if [date] is designated as a working day.
  bool isWorkDay(DateTime date) => workDays.contains(date.weekday);

  /// Returns the exact work hours interval for a given date, or null if it is a non-work day.
  TimeRange? getWorkWindow(DateTime date) {
    if (!isWorkDay(date)) return null;

    final start = DateTime(
      date.year,
      date.month,
      date.day,
      startHour,
      startMinute,
    );
    final end = DateTime(
      date.year,
      date.month,
      date.day,
      endHour,
      endMinute,
    );

    return TimeRange(start: start, end: end);
  }

  /// Returns the allowable waking off-work windows for personal events on [date].
  ///
  /// Typically avoids early morning (before [wakingHour]) and late night (after [sleepHour]).
  List<TimeRange> getOffWorkWindows(
    DateTime date, {
    int wakingHour = 7,
    int sleepHour = 23,
  }) {
    final dayWake = DateTime(date.year, date.month, date.day, wakingHour, 0);
    final daySleep = DateTime(date.year, date.month, date.day, sleepHour, 0);

    if (!isWorkDay(date)) {
      // Entire active day is available for personal events on weekends / days off
      return [TimeRange(start: dayWake, end: daySleep)];
    }

    final work = getWorkWindow(date)!;
    final List<TimeRange> windows = [];

    // Early morning before work (e.g. 07:00 - 08:00)
    if (dayWake.isBefore(work.start)) {
      windows.add(TimeRange(start: dayWake, end: work.start));
    }

    // Evening after work (e.g. 18:00 - 23:00)
    if (work.end.isBefore(daySleep)) {
      windows.add(TimeRange(start: work.end, end: daySleep));
    }

    return windows;
  }
}
