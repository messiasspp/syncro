import '../models/time_range.dart';

/// Algorithmic service providing pure, deterministic interval math operations:
/// - Sweepline Interval Merging: O(N log N)
/// - Disjoint Interval Intersection: O(N + M)
/// - Interval Subtraction (Carving busy blocks out of available windows): O(N + M)
/// - Candidate Slot Slicing: O(Total Duration / step)
class IntervalMath {
  /// Collapses overlapping or abutting intervals into a canonical list of disjoint, sorted intervals.
  ///
  /// Example:
  /// `[10:00 - 11:00]` and `[10:30 - 12:00]` becomes `[10:00 - 12:00]`.
  /// Abutting intervals `[10:00 - 11:00]` and `[11:00 - 12:00]` are also merged.
  static List<TimeRange> mergeOverlapping(List<TimeRange> ranges) {
    if (ranges.isEmpty) return const [];
    if (ranges.length == 1) return [ranges.first];

    final sorted = List<TimeRange>.from(ranges)..sort();
    final List<TimeRange> merged = [];

    var current = sorted.first;

    for (int i = 1; i < sorted.length; i++) {
      final next = sorted[i];

      // Overlapping or abutting: next.start <= current.end
      if (next.start.isBefore(current.end) || next.start.isAtSameMomentAs(current.end)) {
        final latestEnd = next.end.isAfter(current.end) ? next.end : current.end;
        current = TimeRange(start: current.start, end: latestEnd);
      } else {
        merged.add(current);
        current = next;
      }
    }

    merged.add(current);
    return merged;
  }

  /// Two-pointer sweepline algorithm to intersect two lists of sorted disjoint intervals.
  ///
  /// Runs in optimal O(N + M) time.
  static List<TimeRange> intersectLists(
    List<TimeRange> listA,
    List<TimeRange> listB,
  ) {
    final mergedA = mergeOverlapping(listA);
    final mergedB = mergeOverlapping(listB);

    final List<TimeRange> intersections = [];
    int i = 0;
    int j = 0;

    while (i < mergedA.length && j < mergedB.length) {
      final a = mergedA[i];
      final b = mergedB[j];

      final overlap = a.intersection(b);
      if (overlap != null && overlap.duration > Duration.zero) {
        intersections.add(overlap);
      }

      // Advance the interval that ends earlier
      if (a.end.isBefore(b.end)) {
        i++;
      } else if (b.end.isBefore(a.end)) {
        j++;
      } else {
        i++;
        j++;
      }
    }

    return intersections;
  }

  /// Subtracts a list of [busy] intervals from [available] windows.
  ///
  /// Returns the remaining disjoint intervals where an event may be scheduled.
  ///
  /// Mathematical foundation:
  /// Available: [09:00 -------------- 17:00]
  /// Busy:             [11:00 --- 13:00]
  /// Result:    [09:00 - 11:00]   [13:00 - 17:00]
  static List<TimeRange> subtractIntervals({
    required List<TimeRange> available,
    required List<TimeRange> busy,
  }) {
    if (available.isEmpty) return const [];
    if (busy.isEmpty) return mergeOverlapping(available);

    final mergedAvailable = mergeOverlapping(available);
    final mergedBusy = mergeOverlapping(busy);

    final List<TimeRange> freeRanges = [];

    for (final avail in mergedAvailable) {
      DateTime currentCursor = avail.start;

      for (final b in mergedBusy) {
        // Busy slot is completely before our current window
        if (!b.end.isAfter(currentCursor)) continue;

        // Busy slot is completely past our available window
        if (!b.start.isBefore(avail.end)) break;

        // There is a gap between currentCursor and start of busy block
        if (b.start.isAfter(currentCursor)) {
          final gapEnd = b.start.isBefore(avail.end) ? b.start : avail.end;
          if (gapEnd.isAfter(currentCursor)) {
            freeRanges.add(TimeRange(start: currentCursor, end: gapEnd));
          }
        }

        // Advance cursor to end of busy block
        if (b.end.isAfter(currentCursor)) {
          currentCursor = b.end;
        }

        if (!currentCursor.isBefore(avail.end)) {
          break;
        }
      }

      // Any remaining free time after the last busy block in this window
      if (currentCursor.isBefore(avail.end)) {
        freeRanges.add(TimeRange(start: currentCursor, end: avail.end));
      }
    }

    return freeRanges;
  }

  /// Slices continuous free intervals into discrete candidate slots of [slotDuration]
  /// stepping forward by [step] (e.g. 15-minute or 30-minute alignment grid).
  static List<TimeRange> sliceIntoSlots({
    required List<TimeRange> freeIntervals,
    required Duration slotDuration,
    required Duration step,
  }) {
    require(slotDuration > Duration.zero, 'slotDuration must be positive');
    require(step > Duration.zero, 'step must be positive');

    final List<TimeRange> slots = [];

    for (final interval in freeIntervals) {
      if (interval.duration < slotDuration) continue;

      DateTime slotStart = interval.start;
      while (true) {
        final slotEnd = slotStart.add(slotDuration);
        if (slotEnd.isAfter(interval.end)) {
          break;
        }

        slots.add(TimeRange(start: slotStart, end: slotEnd));
        slotStart = slotStart.add(step);
      }
    }

    return slots;
  }
}
