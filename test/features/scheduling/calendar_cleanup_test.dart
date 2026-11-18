import 'package:flutter_test/flutter_test.dart';
import 'package:syncro/features/scheduling/data/calendar/calendar_client.dart';
import 'package:syncro/features/scheduling/data/calendar/google_cloud_calendar_service.dart';
import 'package:syncro/features/scheduling/data/repositories/scheduling_repository.dart';
import 'package:syncro/features/scheduling/domain/models/appointment.dart';
import 'package:syncro/features/scheduling/domain/models/entity.dart';
import 'package:syncro/features/scheduling/domain/models/event_type.dart';
import 'package:syncro/features/scheduling/domain/models/external_calendar.dart';
import 'package:syncro/features/scheduling/domain/models/time_range.dart';
import 'package:syncro/features/scheduling/domain/services/calendar_sync_service.dart';

void main() {
  late InMemorySchedulingRepository repo;
  late InMemoryCalendarClient calendarClient;
  late CalendarSyncService syncService;

  setUp(() {
    repo = InMemorySchedulingRepository();
    calendarClient = InMemoryCalendarClient(
      initialCalendars: const [
        ExternalCalendar(
          id: 'cal_gmail',
          name: 'soaresmessiasg130@gmail.com',
          accountName: 'soaresmessiasg130@gmail.com',
          colorHex: '#4285F4',
        ),
        ExternalCalendar(
          id: 'syncro_dup_1',
          name: 'Syncro — Friends',
          accountName: 'Syncro',
          colorHex: '#8B5CF6',
        ),
        ExternalCalendar(
          id: 'syncro_dup_2',
          name: 'Syncro — Work',
          accountName: 'Syncro',
          colorHex: '#14B8A6',
        ),
      ],
    );
    syncService = CalendarSyncService(
      repository: repo,
      calendarClient: calendarClient,
    );
  });

  test('audit and cleanup removes Syncro calendars & events while preserving user events', () async {
    final now = DateTime.now();
    // 1. Add a normal user event and a Syncro-tagged event inside Gmail calendar
    await calendarClient.createOrUpdateEvent(
      ExternalCalendarEvent(
        externalEventId: 'user_evt_1',
        calendarId: 'cal_gmail',
        title: 'Dentist Appointment',
        description: 'Regular checkup',
        timeRange: TimeRange(
          start: now.add(const Duration(days: 1, hours: 10)),
          end: now.add(const Duration(days: 1, hours: 11)),
        ),
      ),
    );
    final syncroExtId = await calendarClient.createOrUpdateEvent(
      ExternalCalendarEvent(
        calendarId: 'cal_gmail',
        title: 'Friends — Dhaphinne',
        description: 'Scheduled via Syncro Smart Engine\nCategory: Friends',
        timeRange: TimeRange(
          start: now.add(const Duration(days: 2, hours: 19)),
          end: now.add(const Duration(days: 2, hours: 21)),
        ),
      ),
    );

    // 2. Save matching Group and Appointment in SQLite
    await repo.upsertEventType(
      const EventType(
        id: 'et_friends',
        name: 'Friends',
        minDuration: Duration(minutes: 30),
        maxDuration: Duration(minutes: 120),
        calendarMappingId: 'syncro_dup_1',
      ),
    );
    await repo.upsertAppointment(
      Appointment(
        id: 'apt_1',
        entityId: 'Dhaphinne',
        eventTypeId: 'et_friends',
        timeRange: TimeRange(
          start: now.add(const Duration(days: 2, hours: 19)),
          end: now.add(const Duration(days: 2, hours: 21)),
        ),
        status: AppointmentStatus.confirmed,
        externalCalendarEventId: syncroExtId,
      ),
    );

    // 3. Audit
    final audit = await syncService.auditSyncroCalendarData();
    expect(audit.syncroCalendars.length, 2);
    expect(audit.syncroEventsInUserCalendars.length, 1);
    expect(audit.syncroEventsInUserCalendars.first.title, 'Friends — Dhaphinne');

    // 4. Clean
    final result = await syncService.cleanSyncroCalendarData(
      calendarIdsToDelete: audit.syncroCalendars.map((c) => c.id).toList(),
      eventsToDelete: audit.syncroEventsInUserCalendars,
    );
    expect(result.deletedCalendarsCount, 2);
    expect(result.deletedEventsCount, 1);
    expect(result.failedCount, 0);

    // 5. Verify Gmail calendar & user's Dentist event remain intact
    final remainingCals = await calendarClient.retrieveRawCalendars();
    expect(remainingCals.map((c) => c.id).toList(), ['cal_gmail']);

    final remainingEvents = await calendarClient.retrieveEvents(
      calendarId: 'cal_gmail',
      range: TimeRange(
        start: now.subtract(const Duration(days: 1)),
        end: now.add(const Duration(days: 10)),
      ),
    );
    expect(remainingEvents.length, 1);
    expect(remainingEvents.first.title, 'Dentist Appointment');

    // 6. Verify SQLite stale links were cleared
    final updatedEt = await repo.getEventTypeById('et_friends');
    expect(updatedEt?.calendarMappingId, isNull);

    final updatedApt = (await repo.getAllAppointments()).first;
    expect(updatedApt.externalCalendarEventId, isNull);
  });

  test('ensureDedicatedCalendarForEventType preserves explicit Route Account calendar mapping', () async {
    final namedClient = InMemoryCalendarClient(
      initialCalendars: const [
        ExternalCalendar(
          id: 'cal_gmail',
          name: 'soaresmessiasg130@gmail.com',
          accountName: 'soaresmessiasg130@gmail.com',
          colorHex: '#4285F4',
        ),
        ExternalCalendar(
          id: 'cal_syncro_default',
          name: 'Syncro',
          accountName: 'soaresmessiasg130@gmail.com',
          colorHex: '#6366F1',
        ),
        ExternalCalendar(
          id: 'cal_friends_google',
          name: 'Friends',
          accountName: 'soaresmessiasg130@gmail.com',
          colorHex: '#8B5CF6',
        ),
      ],
    );
    final service = CalendarSyncService(
      repository: repo,
      calendarClient: namedClient,
    );

    const friendsGroup = EventType(
      id: 'et_friends',
      name: 'Friends',
      minDuration: Duration(minutes: 30),
      maxDuration: Duration(minutes: 120),
      calendarMappingId: 'cal_friends_google',
    );
    await repo.upsertEventType(friendsGroup);

    final mappedId = await service.ensureDedicatedCalendarForEventType(
      friendsGroup,
    );
    expect(mappedId, 'cal_friends_google');

    final persisted = await repo.getEventTypeById('et_friends');
    expect(persisted?.calendarMappingId, 'cal_friends_google');
  });

  test('ensureDedicatedCalendarForEventType provisions default Syncro calendar for new Groups when Cloud API is signed in', () async {
    final cloudService = GoogleCloudCalendarService()
      ..setManualAccessToken(
        'test_token_123',
        email: 'soaresmessiasg130@gmail.com',
      );
    final client = InMemoryCalendarClient(
      initialCalendars: const [
        ExternalCalendar(
          id: 'cal_gmail',
          name: 'soaresmessiasg130@gmail.com',
          accountName: 'soaresmessiasg130@gmail.com',
          colorHex: '#4285F4',
        ),
      ],
    );
    final service = CalendarSyncService(
      repository: repo,
      calendarClient: client,
      cloudService: cloudService,
    );

    const friendsGroup = EventType(
      id: 'et_friends_cloud',
      name: 'Friends',
      colorHex: '#8B5CF6',
      minDuration: Duration(minutes: 30),
      maxDuration: Duration(minutes: 120),
    );
    await repo.upsertEventType(friendsGroup);

    final mappedId = await service.ensureDedicatedCalendarForEventType(
      friendsGroup,
    );
    final defaultId = await service.ensureDefaultSyncroCalendar();
    expect(mappedId, defaultId);

    final cals = await client.retrieveCalendars();
    final created = cals.where((c) => c.id == mappedId).firstOrNull;
    expect(created, isNotNull);
    expect(created!.name, CalendarSyncService.defaultCalendarName);

    final persisted = await repo.getEventTypeById('et_friends_cloud');
    expect(persisted?.calendarMappingId, mappedId);
  });

  test('EventType generates default 4-char uppercase code (MCS) and formats calendar title as CODE - Name', () async {
    expect(
      EventType.generateDefaultCode('Mounjaro Clinical Study'),
      equals('MCS'),
    );
    expect(EventType.generateDefaultCode('Friends Zone'), equals('FZ'));
    expect(EventType.generateDefaultCode('Friends'), equals('FRI'));
    expect(EventType.sanitizeCode('mc 1!'), equals('MC1'));
    expect(EventType.sanitizeCode('abcd99'), equals('ABCD'));

    const studyGroup = EventType(
      id: 'et_mcs',
      name: 'Mounjaro Clinical Study',
      colorHex: '#14B8A6',
      minDuration: Duration(minutes: 30),
      maxDuration: Duration(minutes: 60),
      calendarMappingId: 'cal_gmail',
    );
    expect(studyGroup.effectiveCode, equals('MCS'));
    await repo.upsertEventType(studyGroup);
    await repo.upsertEntity(
      const Entity(id: 'patient_101', name: 'Patient 101'),
    );

    final slot = TimeRange(
      start: DateTime(2026, 11, 20, 10, 0),
      end: DateTime(2026, 11, 20, 10, 45),
    );
    final apt = Appointment(
      id: 'apt_mcs_1',
      entityId: 'patient_101',
      eventTypeId: 'et_mcs',
      timeRange: slot,
      status: AppointmentStatus.confirmed,
      visitIndex: 0,
    );
    await repo.upsertAppointment(apt);

    final pushed = await syncService.pushAppointmentToCalendar(apt);
    var events = await calendarClient.retrieveEvents(
      calendarId: 'cal_gmail',
      range: TimeRange(
        start: DateTime(2026, 11, 20, 0, 0),
        end: DateTime(2026, 11, 21, 0, 0),
      ),
    );
    expect(events.length, equals(1));
    expect(events.first.title, equals('MCS - Patient 101 (Visit #1)'));

    // Edit code from default MCS -> MC1 and re-sync
    await repo.upsertEventType(studyGroup.copyWith(code: 'MC1'));
    await syncService.pushAppointmentToCalendar(pushed);

    events = await calendarClient.retrieveEvents(
      calendarId: 'cal_gmail',
      range: TimeRange(
        start: DateTime(2026, 11, 20, 0, 0),
        end: DateTime(2026, 11, 21, 0, 0),
      ),
    );
    expect(events.length, equals(1));
    expect(events.first.title, equals('MC1 - Patient 101 (Visit #1)'));
  });

  test('syncAll sweeps duplicate and old-code Syncro events across calendars leaving only current code', () async {
    final now = DateTime.now();
    final visitDay = DateTime(now.year, now.month, now.day, 8, 0)
        .add(const Duration(days: 6));
    final slot = TimeRange(
      start: visitDay,
      end: visitDay.add(const Duration(minutes: 45)),
    );

    final multiCalClient = InMemoryCalendarClient(
      initialCalendars: const [
        ExternalCalendar(
          id: 'cal_gmail',
          name: 'soaresmessiasg130@gmail.com',
          accountName: 'soaresmessiasg130@gmail.com',
          colorHex: '#4285F4',
        ),
        ExternalCalendar(
          id: 'cal_syncro',
          name: 'Syncro',
          accountName: 'soaresmessiasg130@gmail.com',
          colorHex: '#6366F1',
        ),
      ],
    );
    final multiService = CalendarSyncService(
      repository: repo,
      calendarClient: multiCalClient,
    );

    // Legacy event with old MCS code sitting in the previous calendar (cal_gmail)
    await multiCalClient.createOrUpdateEvent(
      ExternalCalendarEvent(
        externalEventId: 'legacy_mcs_evt',
        calendarId: 'cal_gmail',
        title: 'MCS - Patient 101 (Visit #2)',
        description:
            'Scheduled via Syncro Smart Engine\nCategory: Mounjaro Clinical Study\nParticipant: Patient 101\nProtocol Visit: #2',
        timeRange: slot,
      ),
    );
    // Outdated duplicate copy inside cal_syncro too
    await multiCalClient.createOrUpdateEvent(
      ExternalCalendarEvent(
        externalEventId: 'stale_dup_syncro_evt',
        calendarId: 'cal_syncro',
        title: 'MCS - Patient 101 (Visit #2)',
        description:
            'Scheduled via Syncro Smart Engine\nCategory: Mounjaro Clinical Study\nParticipant: Patient 101\nProtocol Visit: #2',
        timeRange: slot,
      ),
    );

    const studyGroup = EventType(
      id: 'et_mcs_sweep',
      name: 'Mounjaro Clinical Study',
      code: 'MCSX',
      colorHex: '#14B8A6',
      minDuration: Duration(minutes: 30),
      maxDuration: Duration(minutes: 60),
      calendarMappingId: 'cal_syncro',
    );
    await repo.upsertEventType(studyGroup);
    await repo.upsertEntity(
      const Entity(id: 'patient_101', name: 'Patient 101'),
    );
    await repo.upsertAppointment(
      Appointment(
        id: 'apt_mcsx_2',
        entityId: 'patient_101',
        eventTypeId: 'et_mcs_sweep',
        timeRange: slot,
        status: AppointmentStatus.confirmed,
        visitIndex: 1,
      ),
    );

    await multiService.syncAll();

    final queryRange = TimeRange(
      start: visitDay.subtract(const Duration(hours: 2)),
      end: visitDay.add(const Duration(hours: 2)),
    );
    final gmailEvents = await multiCalClient.retrieveEvents(
      calendarId: 'cal_gmail',
      range: queryRange,
    );
    final syncroEvents = await multiCalClient.retrieveEvents(
      calendarId: 'cal_syncro',
      range: queryRange,
    );

    expect(gmailEvents, isEmpty);
    expect(syncroEvents.length, equals(1));
    expect(syncroEvents.first.title, equals('MCSX - Patient 101 (Visit #2)'));
  });
}
