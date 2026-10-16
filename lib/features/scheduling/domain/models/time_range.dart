/// Represents an immutable continuous time interval [start, end).
///
/// In interval scheduling mathematics, standardizing on half-open intervals
/// [start, end) prevents fencepost errors: an event ending at 10:00 does not
/// collide with an event starting at 10:00.
class TimeRange implements Comparable<TimeRange> {
  final DateTime start;
  final DateTime end;

  TimeRange({required this.start, required this.end}) {
    require(
      !end.isBefore(start),
      'TimeRange end ($end) must be at or after start ($start).',
    );
  }

  /// Total duration of the interval.
  Duration get duration => end.difference(start);

  /// Checks if [instant] falls within this interval [start, end).
  bool contains(DateTime instant) {
    return (instant.isAtSameMomentAs(start) || instant.isAfter(start)) &&
        instant.isBefore(end);
  }

  /// Checks if this interval completely subsumes [other].
  bool containsRange(TimeRange other) {
    return (other.start.isAtSameMomentAs(start) || other.start.isAfter(start)) &&
        (other.end.isAtSameMomentAs(end) || other.end.isBefore(end));
  }

  /// Checks whether this interval has any non-zero duration overlap with [other].
  ///
  /// Since intervals are half-open [start, end), [10:00, 11:00) and [11:00, 12:00)
  /// touch at 11:00 but DO NOT overlap.
  bool overlaps(TimeRange other) {
    return start.isBefore(other.end) && other.start.isBefore(end);
  }

  /// Returns the intersection between this range and [other], or null if they do not overlap.
  TimeRange? intersection(TimeRange other) {
    if (!overlaps(other)) return null;

    final latestStart = start.isAfter(other.start) ? start : other.start;
    final earliestEnd = end.isBefore(other.end) ? end : other.end;

    if (earliestEnd.isBefore(latestStart) || earliestEnd.isAtSameMomentAs(latestStart)) {
      return null;
    }

    return TimeRange(start: latestStart, end: earliestEnd);
  }

  /// Expands this interval on both sides by the specified buffer durations.
  /// Used in calendar scheduling to enforce pre-meeting preparation and post-meeting travel/wrap-up buffers.
  TimeRange expand({Duration before = Duration.zero, Duration after = Duration.zero}) {
    return TimeRange(
      start: start.subtract(before),
      end: end.add(after),
    );
  }

  @override
  int compareTo(TimeRange other) {
    final startComparison = start.compareTo(other.start);
    if (startComparison != 0) return startComparison;
    return end.compareTo(other.end);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeRange &&
          runtimeType == other.runtimeType &&
          start.isAtSameMomentAs(other.start) &&
          end.isAtSameMomentAs(other.end);

  @override
  int get hashCode => start.hashCode ^ end.hashCode;

  @override
  String toString() => 'TimeRange($start -> $end, duration: ${duration.inMinutes}m)';
}

void require(bool condition, String message) {
  if (!condition) {
    throw ArgumentError(message);
  }
}
