import 'appointment.dart';
import 'external_calendar.dart';

/// Represents a detected scheduling collision between an internal Syncro [Appointment]
/// and an external calendar event (from Google Calendar, Apple Calendar, or Outlook).
class ConflictReport {
  final Appointment appointment;
  final ExternalCalendarEvent conflictingEvent;
  final String calendarName;

  const ConflictReport({
    required this.appointment,
    required this.conflictingEvent,
    required this.calendarName,
  });

  /// The duration of the overlapping interval between the appointment and external event.
  Duration get overlapDuration {
    final start = appointment.timeRange.start.isAfter(conflictingEvent.timeRange.start)
        ? appointment.timeRange.start
        : conflictingEvent.timeRange.start;
    final end = appointment.timeRange.end.isBefore(conflictingEvent.timeRange.end)
        ? appointment.timeRange.end
        : conflictingEvent.timeRange.end;
    return end.isAfter(start) ? end.difference(start) : Duration.zero;
  }
}
