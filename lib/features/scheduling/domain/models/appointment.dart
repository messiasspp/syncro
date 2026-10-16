import 'time_range.dart';

enum AppointmentStatus {
  suggested,
  confirmed,
  completed,
  cancelled,
}

/// A scheduled or proposed calendar appointment.
class Appointment {
  final String id;
  final String entityId;
  final String eventTypeId;
  final TimeRange timeRange;
  final AppointmentStatus status;
  final int? visitIndex;
  final String? protocolEnrollmentId;
  final String? externalCalendarEventId;

  const Appointment({
    required this.id,
    required this.entityId,
    required this.eventTypeId,
    required this.timeRange,
    this.status = AppointmentStatus.suggested,
    this.visitIndex,
    this.protocolEnrollmentId,
    this.externalCalendarEventId,
  });

  Appointment copyWith({
    String? id,
    String? entityId,
    String? eventTypeId,
    TimeRange? timeRange,
    AppointmentStatus? status,
    int? visitIndex,
    String? protocolEnrollmentId,
    String? externalCalendarEventId,
  }) {
    return Appointment(
      id: id ?? this.id,
      entityId: entityId ?? this.entityId,
      eventTypeId: eventTypeId ?? this.eventTypeId,
      timeRange: timeRange ?? this.timeRange,
      status: status ?? this.status,
      visitIndex: visitIndex ?? this.visitIndex,
      protocolEnrollmentId: protocolEnrollmentId ?? this.protocolEnrollmentId,
      externalCalendarEventId:
          externalCalendarEventId ?? this.externalCalendarEventId,
    );
  }
}
