import 'time_range.dart';

/// Models a multi-visit sequence roadmap (e.g., a 1-year clinical trial with 24 visits).
class ProtocolEnrollment {
  final String id;
  final String entityId;
  final String eventTypeId;
  final String protocolName;
  final DateTime startDate;
  final int totalVisits;
  final int cadenceDays;
  final int toleranceWindowDays;

  const ProtocolEnrollment({
    required this.id,
    required this.entityId,
    required this.eventTypeId,
    required this.protocolName,
    required this.startDate,
    this.totalVisits = 24,
    this.cadenceDays = 14,
    this.toleranceWindowDays = 3,
  });

  /// Computes the nominal target date for visit [visitIndex].
  DateTime nominalDateForVisit(int visitIndex) {
    return startDate.add(Duration(days: visitIndex * cadenceDays));
  }

  /// Computes the valid date window [target - tolerance, target + tolerance] for visit [visitIndex].
  TimeRange targetWindowForVisit(int visitIndex) {
    final nominal = nominalDateForVisit(visitIndex);
    final startOfWindow = DateTime(
      nominal.year,
      nominal.month,
      nominal.day - toleranceWindowDays,
      0,
      0,
    );
    final endOfWindow = DateTime(
      nominal.year,
      nominal.month,
      nominal.day + toleranceWindowDays,
      23,
      59,
      59,
    );
    return TimeRange(start: startOfWindow, end: endOfWindow);
  }
}
