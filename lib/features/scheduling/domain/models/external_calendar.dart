import 'time_range.dart';

/// Metadata for a calendar account/sub-calendar on the user's device
/// (e.g. Google Calendar, Apple iCloud Calendar, or a dedicated Syncro sub-calendar).
class ExternalCalendar {
  final String id;
  final String name;
  final String? accountName;
  final String colorHex;
  final bool isReadOnly;

  const ExternalCalendar({
    required this.id,
    required this.name,
    this.accountName,
    this.colorHex = '#2196F3',
    this.isReadOnly = false,
  });
}

/// Represents a concrete calendar event read from or written to an [ExternalCalendar].
class ExternalCalendarEvent {
  final String? externalEventId;
  final String calendarId;
  final String title;
  final String? description;
  final TimeRange timeRange;
  final int reminderMinutesBefore;

  const ExternalCalendarEvent({
    this.externalEventId,
    required this.calendarId,
    required this.title,
    this.description,
    required this.timeRange,
    this.reminderMinutesBefore = 30,
  });

  ExternalCalendarEvent copyWith({
    String? externalEventId,
    String? calendarId,
    String? title,
    String? description,
    TimeRange? timeRange,
    int? reminderMinutesBefore,
  }) {
    return ExternalCalendarEvent(
      externalEventId: externalEventId ?? this.externalEventId,
      calendarId: calendarId ?? this.calendarId,
      title: title ?? this.title,
      description: description ?? this.description,
      timeRange: timeRange ?? this.timeRange,
      reminderMinutesBefore:
          reminderMinutesBefore ?? this.reminderMinutesBefore,
    );
  }
}

/// Summary report returned after executing a two-way synchronization pass.
class CalendarSyncResult {
  final int createdCalendarsCount;
  final int pushedAppointmentsCount;
  final int updatedAppointmentsCount;
  final int externalBusyEventsCount;
  final List<String> errors;

  const CalendarSyncResult({
    this.createdCalendarsCount = 0,
    this.pushedAppointmentsCount = 0,
    this.updatedAppointmentsCount = 0,
    this.externalBusyEventsCount = 0,
    this.errors = const [],
  });

  bool get isSuccess => errors.isEmpty;
}
