import '../models/entity.dart';
import '../models/event_type.dart';
import '../models/time_range.dart';
import '../models/work_schedule.dart';
import 'interval_math.dart';

/// Algorithmic engine that searches for optimal, collision-free appointment slots
/// given an [EventType], user [WorkSchedule], participant [Entity] constraints,
/// and existing [busySlots].
class SlotFinder {
  /// Evaluates and returns sorted candidate slots for the given parameters.
  static List<TimeRange> findCandidateSlots({
    required TimeRange searchRange,
    required EventType eventType,
    required WorkSchedule workSchedule,
    Entity? entity,
    List<TimeRange> busySlots = const [],
    Duration slotStep = const Duration(minutes: 15),
    DateTime? preferredTargetTime,
  }) {
    final List<TimeRange> allowedWindows = [];

    // 1. Iterate through each day in searchRange and compute allowable intervals
    var currentDay = DateTime(
      searchRange.start.year,
      searchRange.start.month,
      searchRange.start.day,
    );
    final endDay = DateTime(
      searchRange.end.year,
      searchRange.end.month,
      searchRange.end.day,
    );

    while (!currentDay.isAfter(endDay)) {
      final dayWindows = _computeAllowedWindowsForDay(
        date: currentDay,
        eventType: eventType,
        workSchedule: workSchedule,
        entity: entity,
      );
      allowedWindows.addAll(dayWindows);
      currentDay = currentDay.add(const Duration(days: 1));
    }

    // Intersect allowedWindows with searchRange boundaries
    final boundedAllowed = allowedWindows
        .map((w) => w.intersection(searchRange))
        .whereType<TimeRange>()
        .toList();

    if (boundedAllowed.isEmpty) return const [];

    // 2. Dilate busy slots with pre- and post-buffers (Minkowski buffer expansion)
    // To ensure a candidate slot has `eventType.bufferBefore` free time before it
    // and `eventType.bufferAfter` free time after it:
    final dilatedBusySlots = busySlots.map((b) {
      return TimeRange(
        start: b.start.subtract(eventType.bufferAfter),
        end: b.end.add(eventType.bufferBefore),
      );
    }).toList();

    // 3. Subtract dilated busy slots from allowable windows
    final freeIntervals = IntervalMath.subtractIntervals(
      available: boundedAllowed,
      busy: dilatedBusySlots,
    );

    // 4. Slice remaining free intervals into candidate slots
    final candidateSlots = IntervalMath.sliceIntoSlots(
      freeIntervals: freeIntervals,
      slotDuration: eventType.minDuration,
      step: slotStep,
    );

    // 5. Rank slots: prefer closest to preferredTargetTime (if supplied) or earliest
    if (preferredTargetTime != null) {
      candidateSlots.sort((a, b) {
        final diffA = (a.start.difference(preferredTargetTime)).abs();
        final diffB = (b.start.difference(preferredTargetTime)).abs();
        return diffA.compareTo(diffB);
      });
    }

    return candidateSlots;
  }

  /// Calculates allowed windows for a specific day by combining:
  /// - WorkHoursConstraint (work_hours_only vs outside_work_hours vs both_flexible)
  /// - EventType.allowedTimeWindows (e.g. Mon/Wed 08:00 - 12:00)
  /// - Entity.customAvailabilityOverrides (e.g. Patient 102 only after 10:00)
  static List<TimeRange> _computeAllowedWindowsForDay({
    required DateTime date,
    required EventType eventType,
    required WorkSchedule workSchedule,
    Entity? entity,
  }) {
    List<TimeRange> baseWindows;

    switch (eventType.workHoursConstraint) {
      case WorkHoursConstraint.workHoursOnly:
        final workWindow = workSchedule.getWorkWindow(date);
        if (workWindow == null) return const [];
        baseWindows = [workWindow];
        break;

      case WorkHoursConstraint.outsideWorkHours:
        baseWindows = workSchedule.getOffWorkWindows(date);
        break;

      case WorkHoursConstraint.bothFlexible:
        baseWindows = [
          TimeRange(
            start: DateTime(date.year, date.month, date.day, 7, 0),
            end: DateTime(date.year, date.month, date.day, 23, 0),
          )
        ];
        break;
    }

    // Intersect with EventType allowed weekly windows (if specified)
    if (eventType.allowedTimeWindows.isNotEmpty) {
      final matchingTypeWindows = eventType.allowedTimeWindows
          .where((w) => w.dayOfWeek == date.weekday)
          .map((w) => w.toTimeRange(date))
          .toList();

      if (matchingTypeWindows.isEmpty) return const [];
      baseWindows =
          IntervalMath.intersectLists(baseWindows, matchingTypeWindows);
    }

    // Intersect with Entity custom overrides (if participant has specific restrictions)
    if (entity != null && entity.customAvailabilityOverrides.isNotEmpty) {
      final matchingEntityWindows = entity.customAvailabilityOverrides
          .where((w) => w.dayOfWeek == date.weekday)
          .map((w) => w.toTimeRange(date))
          .toList();

      if (matchingEntityWindows.isEmpty) return const [];
      baseWindows =
          IntervalMath.intersectLists(baseWindows, matchingEntityWindows);
    }

    return baseWindows;
  }
}
