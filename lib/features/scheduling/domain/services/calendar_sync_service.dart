import 'dart:io';

import '../../data/calendar/calendar_client.dart';
import '../../data/calendar/google_cloud_calendar_service.dart';
import '../../data/repositories/scheduling_repository.dart';
import '../models/appointment.dart';
import '../models/conflict_report.dart';
import '../models/event_type.dart';
import '../models/external_calendar.dart';
import '../models/time_range.dart';
import 'interval_math.dart';
import 'slot_finder.dart';

/// Orchestrates two-way synchronization between Syncro's local SQLite repository
/// and native/external calendars (Google Calendar, Apple Calendar) via [CalendarClient].
class CalendarSyncService {
  static const String defaultCalendarName = 'Syncro';
  static const String defaultCalendarColorHex = '#6366F1';

  final SchedulingRepository _repository;
  final CalendarClient _calendarClient;
  final GoogleCloudCalendarService? _cloudService;

  const CalendarSyncService({
    required SchedulingRepository repository,
    required CalendarClient calendarClient,
    GoogleCloudCalendarService? cloudService,
  })  : _repository = repository,
        _calendarClient = calendarClient,
        _cloudService = cloudService;

  /// Ensures the single default `"Syncro"` cloud calendar exists in the user's
  /// connected Google account (or returns the primary writable `@gmail.com`
  /// calendar if Cloud API is not signed in).
  Future<String?> ensureDefaultSyncroCalendar() async {
    final calendars = await _calendarClient.retrieveCalendars();
    final writableUserCals = calendars
        .where((c) =>
            !c.isReadOnly &&
            c.accountName != 'Syncro' &&
            c.accountName != 'Syncro Local' &&
            !c.name.startsWith('Syncro —'))
        .toList();

    final existingSyncro = writableUserCals
        .where((c) => c.name.trim().toLowerCase() == 'syncro')
        .firstOrNull;
    if (existingSyncro != null) {
      return existingSyncro.id;
    }

    if (_cloudService != null && _cloudService.isSignedIn) {
      return _calendarClient.createDedicatedCalendar(
        name: defaultCalendarName,
        colorHex: defaultCalendarColorHex,
      );
    }

    final primaryGmail = writableUserCals
        .where((c) =>
            c.name.contains('@gmail.com') ||
            (c.accountName?.contains('@gmail.com') ?? false))
        .firstOrNull;
    return (primaryGmail ?? writableUserCals.firstOrNull)?.id;
  }

  /// Ensures a target calendar exists on the device or cloud for [eventType] and
  /// persists its `calendarMappingId`.
  ///
  /// Priority order:
  /// 1. Explicit Route Account mapping (`eventType.calendarMappingId` matching a writable calendar).
  /// 2. Existing default `"Syncro"` calendar on the connected account.
  /// 3. Auto-creates the single default `"Syncro"` cloud calendar when Cloud API is signed in.
  /// 4. On Android/iOS without Cloud API, routes to the primary `@gmail.com` calendar.
  /// 5. Desktop/in-memory fallback.
  Future<String> ensureDedicatedCalendarForEventType(
    EventType eventType,
  ) async {
    final calendars = await _calendarClient.retrieveCalendars();
    final existingMappingId = eventType.calendarMappingId;

    final writableUserCals = calendars
        .where((c) =>
            !c.isReadOnly &&
            c.accountName != 'Syncro' &&
            c.accountName != 'Syncro Local' &&
            !c.name.startsWith('Syncro —'))
        .toList();

    // Priority 1: Explicit Route Account mapping
    if (existingMappingId != null) {
      final existingCal =
          writableUserCals.where((c) => c.id == existingMappingId).firstOrNull;
      if (existingCal != null) {
        return existingCal.id;
      }
    }

    // Priority 2: Existing default "Syncro" calendar
    final existingSyncro = writableUserCals
        .where((c) => c.name.trim().toLowerCase() == 'syncro')
        .firstOrNull;
    if (existingSyncro != null) {
      await _repository.upsertEventType(
        eventType.copyWith(calendarMappingId: existingSyncro.id),
      );
      return existingSyncro.id;
    }

    // Priority 3: Auto-create single default "Syncro" Google Cloud Calendar when signed in
    if (_cloudService != null && _cloudService.isSignedIn) {
      final createdCalendarId = await _calendarClient.createDedicatedCalendar(
        name: defaultCalendarName,
        colorHex: defaultCalendarColorHex,
      );
      await _repository.upsertEventType(
        eventType.copyWith(calendarMappingId: createdCalendarId),
      );
      return createdCalendarId;
    }

    // Priority 4: Mobile fallback to primary @gmail.com calendar when not signed into Cloud API
    if (Platform.isAndroid || Platform.isIOS) {
      final primaryGmail = writableUserCals
          .where((c) =>
              c.name.contains('@gmail.com') ||
              (c.accountName?.contains('@gmail.com') ?? false))
          .firstOrNull;
      final chosen = primaryGmail ?? writableUserCals.firstOrNull;
      if (chosen != null) {
        final updatedEventType = eventType.copyWith(
          calendarMappingId: chosen.id,
        );
        await _repository.upsertEventType(updatedEventType);
        return chosen.id;
      }
    }

    if (existingMappingId != null &&
        calendars.any((c) => c.id == existingMappingId)) {
      return existingMappingId;
    }

    // Priority 5: Desktop / unit test fallback
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
        if (calendar.accountName == 'Syncro' ||
            calendar.accountName == 'Syncro Local' ||
            calendar.name.startsWith('Syncro —')) {
          continue;
        }
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

    final eventType =
        await _repository.getEventTypeById(appointment.eventTypeId);
    if (eventType == null) {
      throw StateError('EventType not found: ${appointment.eventTypeId}');
    }

    final entity = await _repository.getEntityById(appointment.entityId);
    final participantName = entity?.name ?? appointment.entityId;

    final previousMappingId = eventType.calendarMappingId;
    final targetCalendarId =
        await ensureDedicatedCalendarForEventType(eventType);
    final didCalendarChange =
        previousMappingId != null && previousMappingId != targetCalendarId;

    final visitSuffix = appointment.visitIndex != null
        ? ' (Visit #${appointment.visitIndex! + 1})'
        : '';
    final title = '${eventType.effectiveCode} - $participantName$visitSuffix';

    final descriptionBuffer = StringBuffer()
      ..writeln('Scheduled via Syncro Smart Engine')
      ..writeln('Category: ${eventType.name} (${eventType.effectiveCode})')
      ..writeln('Participant: $participantName');
    if (entity?.phone != null) {
      descriptionBuffer.writeln('Phone: ${entity!.phone}');
    }
    if (appointment.visitIndex != null) {
      descriptionBuffer
          .writeln('Protocol Visit: #${appointment.visitIndex! + 1}');
    }

    final externalEvent = ExternalCalendarEvent(
      externalEventId:
          didCalendarChange ? null : appointment.externalCalendarEventId,
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

  /// Deletes an [appointment]'s external calendar event from its dedicated sub-calendar.
  Future<void> deleteAppointmentFromCalendar(Appointment appointment) async {
    final externalEventId = appointment.externalCalendarEventId;
    if (externalEventId == null) return;

    final eventType =
        await _repository.getEventTypeById(appointment.eventTypeId);
    final calendarId = eventType?.calendarMappingId;
    if (calendarId != null) {
      try {
        await _calendarClient.deleteEvent(
          calendarId: calendarId,
          externalEventId: externalEventId,
        );
      } catch (_) {
        // Silently tolerate if external event was already removed externally
      }
    }
  }

  /// Detects collisions between active Syncro appointments and external device calendar events.
  /// Returns a map of appointmentId -> ConflictReport.
  Future<Map<String, ConflictReport>> detectConflicts({TimeRange? range}) async {
    final now = DateTime.now();
    final searchRange = range ??
        TimeRange(
          start: DateTime(now.year - 1, 1, 1),
          end: DateTime(now.year + 2, 12, 31),
        );

    final appointments = await _repository.getAppointmentsInRange(searchRange);
    final activeAppointments = appointments
        .where((a) => a.status != AppointmentStatus.cancelled)
        .toList();

    if (activeAppointments.isEmpty) return const {};

    final hasPerms = await _calendarClient.requestPermissions();
    if (!hasPerms) return const {};

    final calendars = await _calendarClient.retrieveCalendars();
    final Map<String, ConflictReport> conflicts = {};

    for (final calendar in calendars) {
      if (calendar.name.startsWith('Syncro') ||
          calendar.accountName == 'Syncro') {
        continue;
      }

      final externalEvents = await _calendarClient.retrieveEvents(
        calendarId: calendar.id,
        range: searchRange,
      );

      for (final apt in activeAppointments) {
        if (conflicts.containsKey(apt.id)) continue;

        for (final extEvent in externalEvents) {
          // Skip Syncro's own synced copy
          if (apt.externalCalendarEventId != null &&
              extEvent.externalEventId == apt.externalCalendarEventId) {
            continue;
          }

          if (apt.timeRange.overlaps(extEvent.timeRange)) {
            conflicts[apt.id] = ConflictReport(
              appointment: apt,
              conflictingEvent: extEvent,
              calendarName: calendar.name,
            );
            break;
          }
        }
      }
    }

    return conflicts;
  }

  /// Calculates alternative collision-free candidate slots to resolve a conflict for [appointment].
  Future<List<TimeRange>> suggestConflictResolutions(
    Appointment appointment, {
    int maxSuggestions = 3,
  }) async {
    final eventType =
        await _repository.getEventTypeById(appointment.eventTypeId);
    final entity = await _repository.getEntityById(appointment.entityId);
    final workSchedule = await _repository.getWorkSchedule();

    if (eventType == null) return const [];

    // Search window anchored around the appointment's scheduled date:
    // ±7 days window to find optimal nearby slots
    final aptStart = appointment.timeRange.start;
    final searchWindow = TimeRange(
      start: DateTime(aptStart.year, aptStart.month, aptStart.day)
          .subtract(const Duration(days: 2)),
      end: DateTime(aptStart.year, aptStart.month, aptStart.day)
          .add(const Duration(days: 8, hours: 23, minutes: 59)),
    );

    final busySlots = await fetchMergedBusySlots(
      searchWindow,
      excludeAppointmentId: appointment.id,
    );

    final candidates = SlotFinder.findCandidateSlots(
      searchRange: searchWindow,
      eventType: eventType,
      workSchedule: workSchedule,
      entity: entity,
      busySlots: busySlots,
      slotStep: const Duration(minutes: 30),
    );

    return candidates.take(maxSuggestions).toList();
  }

  /// 1-Tap Auto-Resolve: reschedules [appointment] to [newSlot], updates SQLite,
  /// and updates native calendar event.
  Future<Appointment> autoResolveConflict({
    required Appointment appointment,
    required TimeRange newSlot,
  }) async {
    final updated = appointment.copyWith(timeRange: newSlot);
    await _repository.upsertAppointment(updated);
    if (updated.status != AppointmentStatus.cancelled) {
      await pushAppointmentToCalendar(updated);
    }
    return updated;
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

  /// Audits all device calendars to find orphaned local Syncro calendars,
  /// other local (non-cloud) calendars, and Syncro-created events inside
  /// user cloud calendars (e.g. Google Calendar).
  Future<SyncroCalendarAudit> auditSyncroCalendarData() async {
    final hasPerms = await _calendarClient.requestPermissions();
    if (!hasPerms) {
      return const SyncroCalendarAudit(
        syncroCalendars: [],
        otherLocalCalendars: [],
        syncroEventsInUserCalendars: [],
      );
    }

    final rawCalendars = await _calendarClient.retrieveRawCalendars();
    final appointments = await _repository.getAllAppointments();
    final knownExternalIds = {
      for (final apt in appointments)
        if (apt.externalCalendarEventId != null) apt.externalCalendarEventId!,
    };

    final List<ExternalCalendar> syncroCalendars = [];
    final List<ExternalCalendar> otherLocalCalendars = [];
    final List<ExternalCalendar> userCalendars = [];

    for (final cal in rawCalendars) {
      final acct = (cal.accountName ?? '').trim();
      final isDemoCal =
          cal.name == 'Friends Zone' || cal.name == 'Mounjaro Clinical Study';
      final isSyncroCal = acct == 'Syncro' ||
          acct == 'Syncro Local' ||
          cal.name.startsWith('Syncro') ||
          isDemoCal;
      if (isSyncroCal) {
        syncroCalendars.add(cal);
        continue;
      }

      final isCloudAccount =
          acct.contains('@') || acct.toLowerCase() == 'icloud';
      if (!cal.isReadOnly && !isCloudAccount) {
        otherLocalCalendars.add(cal);
      }
      userCalendars.add(cal);
    }

    if (_cloudService != null && _cloudService.isSignedIn) {
      try {
        final managedCloudCals =
            await _cloudService.listSyncroManagedCloudCalendars();
        final existingIds = syncroCalendars.map((c) => c.id).toSet();
        final existingNames =
            syncroCalendars.map((c) => c.name.trim().toLowerCase()).toSet();
        for (final cal in managedCloudCals) {
          if (!existingIds.contains(cal.id) &&
              !existingNames.contains(cal.name.trim().toLowerCase())) {
            syncroCalendars.add(cal);
          }
        }
      } catch (_) {}
    }

    final now = DateTime.now();
    final searchRange = TimeRange(
      start: DateTime(now.year - 2, 1, 1),
      end: DateTime(now.year + 3, 12, 31),
    );

    final List<ExternalCalendarEvent> syncroEventsInUserCalendars = [];
    for (final cal in userCalendars) {
      if (cal.isReadOnly) continue;
      try {
        final events = await _calendarClient.retrieveEvents(
          calendarId: cal.id,
          range: searchRange,
        );
        for (final evt in events) {
          final isSyncroDesc = evt.description != null &&
              evt.description!.contains('Scheduled via Syncro Smart Engine');
          final isKnownId = evt.externalEventId != null &&
              knownExternalIds.contains(evt.externalEventId);
          if (isSyncroDesc || isKnownId) {
            syncroEventsInUserCalendars.add(evt);
          }
        }
      } catch (_) {}
    }

    return SyncroCalendarAudit(
      syncroCalendars: syncroCalendars,
      otherLocalCalendars: otherLocalCalendars,
      syncroEventsInUserCalendars: syncroEventsInUserCalendars,
    );
  }

  /// Deletes the selected Syncro local calendars and/or Syncro-created events
  /// from device/Google calendars, and clears stale external IDs in SQLite.
  Future<SyncroCleanupResult> cleanSyncroCalendarData({
    required List<String> calendarIdsToDelete,
    required List<ExternalCalendarEvent> eventsToDelete,
  }) async {
    int deletedCalendars = 0;
    int deletedEvents = 0;
    int failedCount = 0;

    final deletedCalSet = calendarIdsToDelete.toSet();
    final List<ExternalCalendar> rawCals = deletedCalSet.isNotEmpty
        ? await _calendarClient.retrieveRawCalendars()
        : const [];
    final List<ExternalCalendar> cloudCals =
        (deletedCalSet.isNotEmpty &&
                _cloudService != null &&
                _cloudService.isSignedIn)
            ? await _cloudService.listCloudCalendars().catchError(
                  (_) => const <ExternalCalendar>[],
                )
            : const [];

    for (final calId in calendarIdsToDelete) {
      var ok = false;
      final rawCal = rawCals.where((c) => c.id == calId).firstOrNull;

      if (_cloudService != null && _cloudService.isSignedIn) {
        final cloudMatch = cloudCals
            .where((c) =>
                c.id == calId ||
                (rawCal != null &&
                    c.name.trim().toLowerCase() ==
                        rawCal.name.trim().toLowerCase()))
            .firstOrNull;
        if (cloudMatch != null) {
          try {
            ok = await _cloudService.deleteCloudCalendar(cloudMatch.id);
          } catch (_) {}
        }
      }

      if (!ok) {
        try {
          ok = await _calendarClient.deleteCalendar(calId);
        } catch (_) {}
      }

      if (ok) {
        deletedCalendars++;
      } else {
        failedCount++;
      }
    }

    // Clear calendarMappingId on any EventType pointing to a deleted calendar
    if (deletedCalSet.isNotEmpty) {
      final eventTypes = await _repository.getAllEventTypes();
      for (final et in eventTypes) {
        if (et.calendarMappingId != null &&
            deletedCalSet.contains(et.calendarMappingId)) {
          await _repository.upsertEventType(
            et.copyWith(clearCalendarMappingId: true),
          );
        }
      }
    }

    final Set<String> deletedEventIds = {};
    for (final evt in eventsToDelete) {
      final extId = evt.externalEventId;
      if (extId == null) continue;
      try {
        final ok = await _calendarClient.deleteEvent(
          calendarId: evt.calendarId,
          externalEventId: extId,
        );
        if (ok) {
          deletedEvents++;
          deletedEventIds.add(extId);
        } else {
          failedCount++;
        }
      } catch (_) {
        failedCount++;
      }
    }

    // Clear externalCalendarEventId on any Appointment whose external event was removed
    // or whose Group's calendar was deleted.
    final appointments = await _repository.getAllAppointments();
    final eventTypes = await _repository.getAllEventTypes();
    final mappedCalByEventType = {
      for (final et in eventTypes) et.id: et.calendarMappingId,
    };

    for (final apt in appointments) {
      final extId = apt.externalCalendarEventId;
      if (extId == null) continue;
      final groupCalId = mappedCalByEventType[apt.eventTypeId];
      if (deletedEventIds.contains(extId) ||
          (groupCalId != null && deletedCalSet.contains(groupCalId)) ||
          deletedCalSet.isNotEmpty && groupCalId == null) {
        await _repository.upsertAppointment(
          apt.copyWith(clearExternalCalendarEventId: true),
        );
      }
    }

    return SyncroCleanupResult(
      deletedCalendarsCount: deletedCalendars,
      deletedEventsCount: deletedEvents,
      failedCount: failedCount,
    );
  }
}

/// Snapshot of Syncro-created calendars and events currently on the device.
class SyncroCalendarAudit {
  final List<ExternalCalendar> syncroCalendars;
  final List<ExternalCalendar> otherLocalCalendars;
  final List<ExternalCalendarEvent> syncroEventsInUserCalendars;

  const SyncroCalendarAudit({
    required this.syncroCalendars,
    required this.otherLocalCalendars,
    required this.syncroEventsInUserCalendars,
  });

  bool get isEmpty =>
      syncroCalendars.isEmpty &&
      otherLocalCalendars.isEmpty &&
      syncroEventsInUserCalendars.isEmpty;
}

/// Outcome report returned after running [CalendarSyncService.cleanSyncroCalendarData].
class SyncroCleanupResult {
  final int deletedCalendarsCount;
  final int deletedEventsCount;
  final int failedCount;

  const SyncroCleanupResult({
    required this.deletedCalendarsCount,
    required this.deletedEventsCount,
    required this.failedCount,
  });
}
