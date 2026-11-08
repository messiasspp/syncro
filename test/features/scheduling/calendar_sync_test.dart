import 'package:flutter_test/flutter_test.dart';
import 'package:syncro/features/scheduling/data/calendar/calendar_client.dart';
import 'package:syncro/features/scheduling/data/repositories/scheduling_repository.dart';
import 'package:syncro/features/scheduling/data/seed/demo_seed_service.dart';
import 'package:syncro/features/scheduling/domain/models/external_calendar.dart';
import 'package:syncro/features/scheduling/domain/models/time_range.dart';
import 'package:syncro/features/scheduling/domain/services/calendar_sync_service.dart';
import 'package:syncro/features/scheduling/domain/services/slot_finder.dart';

void main() {
  group('CalendarSyncService - Dedicated Sub-Calendars & Two-Way Sync', () {
    late InMemorySchedulingRepository repository;
    late InMemoryCalendarClient calendarClient;
    late DemoSeedService seeder;
    late CalendarSyncService syncService;

    setUp(() async {
      repository = InMemorySchedulingRepository();
      calendarClient = InMemoryCalendarClient();
      seeder = DemoSeedService(repository);
      syncService = CalendarSyncService(
        repository: repository,
        calendarClient: calendarClient,
      );

      await seeder.resetAndSeed(referenceDate: DateTime(2026, 10, 19));
    });

    test('ensureDedicatedCalendarForEventType creates sub-calendar and persists calendarMappingId', () async {
      final mounjaroType = await repository.getEventTypeById(
        DemoSeedService.mounjaroStudyTypeId,
      );
      expect(mounjaroType, isNotNull);
      expect(mounjaroType!.calendarMappingId, isNull);

      final calendarId = await syncService.ensureDedicatedCalendarForEventType(
        mounjaroType,
      );
      expect(calendarId.isNotEmpty, true);

      // Verify the mapping ID was saved back to the repository
      final updatedType = await repository.getEventTypeById(
        DemoSeedService.mounjaroStudyTypeId,
      );
      expect(updatedType!.calendarMappingId, calendarId);

      // Verify the dedicated calendar appears in the device calendar list
      final deviceCalendars = await calendarClient.retrieveCalendars();
      final createdCal = deviceCalendars.firstWhere((c) => c.id == calendarId);
      expect(createdCal.name, 'Syncro — Mounjaro Clinical Study');
      expect(createdCal.colorHex, '#00897B');
    });

    test('syncAll provisions sub-calendars and pushes Mounjaro instantAuto visits', () async {
      final result = await syncService.syncAll();

      expect(result.isSuccess, true);
      expect(result.createdCalendarsCount, 2); // Friends Zone + Mounjaro Study
      // Mounjaro Study has instantAuto mode (48 visits across Patient 101 & Patient 102)
      expect(result.pushedAppointmentsCount, 48);
      expect(result.updatedAppointmentsCount, 0);

      // Subsequent syncAll updates existing external events rather than duplicating
      final secondResult = await syncService.syncAll();
      expect(secondResult.createdCalendarsCount, 0);
      expect(secondResult.pushedAppointmentsCount, 0);
      expect(secondResult.updatedAppointmentsCount, 48);
    });

    test('fetchMergedBusySlots combines external Google/Apple Calendar events and deduplicates Syncro events', () async {
      // 1. Add an external busy event on Thursday Oct 22, 2026 19:00 - 21:00 on the user's Personal Google Calendar
      await calendarClient.createOrUpdateEvent(
        ExternalCalendarEvent(
          calendarId: 'cal_personal_primary',
          title: 'External Dentist / Dinner',
          timeRange: TimeRange(
            start: DateTime(2026, 10, 22, 19, 0),
            end: DateTime(2026, 10, 22, 21, 0),
          ),
        ),
      );

      final searchRange = TimeRange(
        start: DateTime(2026, 10, 19, 0, 0),
        end: DateTime(2026, 10, 25, 23, 59),
      );

      // Exclude Mendy's initial suggested appointment so we can re-run SlotFinder for Mendy
      final mergedBusy = await syncService.fetchMergedBusySlots(
        searchRange,
        excludeAppointmentId: 'apt_mendy_hangout_1',
      );

      final friendsZoneType = (await repository.getEventTypeById(
        DemoSeedService.friendsZoneTypeId,
      ))!;
      final mendy = (await repository.getEntityById(
        DemoSeedService.mendyEntityId,
      ))!;
      final workSchedule = await repository.getWorkSchedule();

      final availableSlots = SlotFinder.findCandidateSlots(
        searchRange: searchRange,
        eventType: friendsZoneType,
        workSchedule: workSchedule,
        entity: mendy,
        busySlots: mergedBusy,
        slotStep: const Duration(minutes: 30),
      );

      // Thursday 19:00 - 21:00 is blocked by the external Google Calendar event,
      // leaving only 21:00 - 22:00 (60m) on Thursday or slots on Saturday!
      for (final slot in availableSlots) {
        if (slot.start.weekday == DateTime.thursday) {
          expect(slot.start.hour >= 21, true);
        }
      }
    });
  });
}
