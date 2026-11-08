import '../../data/calendar/calendar_client.dart';
import '../../data/repositories/scheduling_repository.dart';
import '../models/appointment.dart';
import '../models/event_type.dart';
import '../models/external_calendar.dart';
import '../models/time_range.dart';
import 'interval_math.dart';

/// Orchestrates two-way synchronization between Syncro's local SQLite repository
/// and native/external calendars (Google Calendar, Apple Calendar) via [CalendarClient].
class CalendarSyncService {
  final SchedulingRepository _repository;
  final CalendarClient _calendarClient;

  const CalendarSyncService({
    required SchedulingRepository repository,
    required CalendarClient calendarClient,
  })  : _repository = repository,
        _calendarClient = calendarClient;

  /// Ensures a dedicated sub-calendar (e.g., `"Syncro — Mounjaro Clinical Study"`)
  /// exists on the device for [eventType] and persists its `calendarMappingId`.
  Future<String> ensureDedicatedCalendarForEventType(
    EventType eventType,
  ) async {
    final calendars = await _calendarClient.retrieveCalendars();
    final existingMappingId = eventType.calendarMappingId;

    if (existingMappingId != null &&
        calendars.any((c) => c.id == existingMappingId)) {
      return existingMappingId;
    }

    final calendarTitle = 'Syncro — ${eventType.name}';
    final createdCalendarId = await _calendarClient.createDedicatedCalendar(
      name: calendarTitle,
      colorHex: eventType.colorHex,
    );

    final updatedEventType = eventType.copyWith(
      calendarMappingId: createdCalendarId,
    );
    await _repository.upsertEventType(updatedEventType);

    return createdCalendarId;
  }

  /// Aggregates and merges all busy intervals in [searchRange] from both:
  /// 1. Internal Syncro appointments (excluding cancelled or excluded IDs)
  /// 2. External events across all connected device calendars (Google / Apple Calendar),
  ///    automatically deduplicating events already linked via `externalCalendarEventId`.
  Future<List<TimeRange>> fetchMergedBusySlots(
    TimeRange searchRange, {
    String? excludeAppointmentId,
    String? excludeProtocolEnrollmentId,
  }) async {
    final internalAppointments =
        await _repository.getAppointmentsInRange(searchRange);

    final Set<String> knownSyncroExternalIds = {};
    final List<TimeRange> rawBusyRanges = [];

    for (final apt in internalAppointments) {
      if (apt.externalCalendarEventId != null) {
        knownSyncroExternalIds.add(apt.externalCalendarEventId!);
      }

      if (apt.status == AppointmentStatus.cancelled) continue;
      if (excludeAppointmentId != null && apt.id == excludeAppointmentId) {
        continue;
      }
      if (excludeProtocolEnrollmentId != null &&
          apt.protocolEnrollmentId == excludeProtocolEnrollmentId) {
        continue;
      }

      rawBusyRanges.add(apt.timeRange);
    }

    final hasPerms = await _calendarClient.hasPermissions();
    if (hasPerms) {
      final calendars = await _calendarClient.retrieveCalendars();
      for (final calendar in calendars) {
        final externalEvents = await _calendarClient.retrieveEvents(
          calendarId: calendar.id,
          range: searchRange,
        );
        for (final extEvent in externalEvents) {
          // Skip external events that belong to Syncro's own managed appointments
          // so we never double-count or block a slot against its own prior external copy.
          if (extEvent.externalEventId != null &&
              knownSyncroExternalIds.contains(extEvent.externalEventId)) {
            continue;
          }
          rawBusyRanges.add(extEvent.timeRange);
        }
      }
    }

    return IntervalMath.mergeOverlapping(rawBusyRanges);
  }

  /// Pushes or updates a single [appointment] into its EventType's dedicated sub-calendar,
  /// storing the resulting `externalCalendarEventId` back into SQLite.
  Future<Appointment> pushAppointmentToCalendar(
    Appointment appointment,
  ) async {
    final hasPerms = await _calendarClient.requestPermissions();
    if (!hasPerms) {
      throw StateError('Calendar permissions not granted.');
    }

    final eventType = await _repository.getEventTypeById(appointment.eventTypeId);
    if (eventType == null) {
      throw StateError('EventType not found: ${appointment.eventTypeId}');
    }

    final entity = await _repository.getEntityById(appointment.entityId);
    final participantName = entity?.name ?? appointment.entityId;

    final targetCalendarId =
        await ensureDedicatedCalendarForEventType(eventType);

    final visitSuffix = appointment.visitIndex != null
        ? ' (Visit #${appointment.visitIndex! + 1})'
        : '';
    final title = '${eventType.name} — $participantName$visitSuffix';

    final descriptionBuffer = StringBuffer()
      ..writeln('Scheduled via Syncro Smart Engine')
      ..writeln('Category: ${eventType.name}')
      ..writeln('Participant: $participantName');
    if (entity?.phone != null) {
      descriptionBuffer.writeln('Phone: ${entity!.phone}');
    }
    if (appointment.visitIndex != null) {
      descriptionBuffer.writeln('Protocol Visit: #${appointment.visitIndex! + 1}');
    }

    final externalEvent = ExternalCalendarEvent(
      externalEventId: appointment.externalCalendarEventId,
      calendarId: targetCalendarId,
      title: title,
      description: descriptionBuffer.toString().trim(),
      timeRange: appointment.timeRange,
      reminderMinutesBefore: 30,
    );

    final assignedExternalId =
        await _calendarClient.createOrUpdateEvent(externalEvent);

    final updatedAppointment = appointment.copyWith(
      externalCalendarEventId: assignedExternalId,
      status: appointment.status == AppointmentStatus.suggested &&
              eventType.schedulingMode == SchedulingMode.instantAuto
          ? AppointmentStatus.confirmed
          : appointment.status,
    );

    await _repository.upsertAppointment(updatedAppointment);
    return updatedAppointment;
  }

  /// Performs a full two-way synchronization pass across all [EventType]s and
  /// active appointments within [syncWindow].
  Future<CalendarSyncResult> syncAll({
    TimeRange? syncWindow,
    bool autoConfirmInstantMode = true,
  }) async {
    final List<String> errors = [];
    int createdCalendarsCount = 0;
    int pushedCount = 0;
    int updatedCount = 0;
    int externalBusyCount = 0;

    final granted = await _calendarClient.requestPermissions();
    if (!granted) {
      return const CalendarSyncResult(
        errors: ['Calendar permissions were denied by the operating system.'],
      );
    }

    // 1. Ensure dedicated sub-calendars exist for all configured EventTypes
    final eventTypes = await _repository.getAllEventTypes();
    final Map<String, EventType> eventTypesById = {};

    for (final et in eventTypes) {
      try {
        final hadMapping = et.calendarMappingId != null;
        final calId = await ensureDedicatedCalendarForEventType(et);
        if (!hadMapping) {
          createdCalendarsCount++;
        }
        eventTypesById[et.id] = et.copyWith(calendarMappingId: calId);
      } catch (e) {
        errors.add('Failed to provision calendar for ${et.name}: $e');
      }
    }

    // 2. Push/update appointments
    final appointments = syncWindow != null
        ? await _repository.getAppointmentsInRange(syncWindow)
        : await _repository.getAllAppointments();

    for (final apt in appointments) {
      if (apt.status == AppointmentStatus.cancelled) continue;

      final et = eventTypesById[apt.eventTypeId];
      final shouldSync = apt.status == AppointmentStatus.confirmed ||
          (autoConfirmInstantMode &&
              apt.status == AppointmentStatus.suggested &&
              et?.schedulingMode == SchedulingMode.instantAuto);

      if (!shouldSync) continue;

      try {
        final wasAlreadyLinked = apt.externalCalendarEventId != null;
        await pushAppointmentToCalendar(apt);
        if (wasAlreadyLinked) {
          updatedCount++;
        } else {
          pushedCount++;
        }
      } catch (e) {
        errors.add('Failed to sync appointment ${apt.id}: $e');
      }
    }

    // 3. Count external busy events in the window
    if (syncWindow != null) {
      final mergedBusy = await fetchMergedBusySlots(syncWindow);
      externalBusyCount = mergedBusy.length;
    }

    return CalendarSyncResult(
      createdCalendarsCount: createdCalendarsCount,
      pushedAppointmentsCount: pushedCount,
      updatedAppointmentsCount: updatedCount,
      externalBusyEventsCount: externalBusyCount,
      errors: errors,
    );
  }
}
