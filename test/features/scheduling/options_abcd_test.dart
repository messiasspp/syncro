import 'package:flutter_test/flutter_test.dart';
import 'package:syncro/core/l10n/app_strings.dart';
import 'package:syncro/features/scheduling/data/calendar/calendar_client.dart';
import 'package:syncro/features/scheduling/data/repositories/scheduling_repository.dart';
import 'package:syncro/features/scheduling/data/seed/demo_seed_service.dart';
import 'package:syncro/features/scheduling/domain/models/appointment.dart';
import 'package:syncro/features/scheduling/domain/models/entity.dart';
import 'package:syncro/features/scheduling/domain/models/event_type.dart';
import 'package:syncro/features/scheduling/domain/models/protocol_enrollment.dart';
import 'package:syncro/features/scheduling/domain/models/time_range.dart';
import 'package:syncro/features/scheduling/domain/models/work_schedule.dart';
import 'package:syncro/features/scheduling/domain/services/calendar_sync_service.dart';
import 'package:syncro/features/scheduling/domain/services/protocol_cascade_service.dart';
import 'package:syncro/features/scheduling/domain/services/slot_finder.dart';

void main() {
  group('Options A, B, C & D Verification Suite', () {
    late InMemorySchedulingRepository repo;
    late InMemoryCalendarClient calendarClient;
    late CalendarSyncService syncService;

    const workSchedule = WorkSchedule(
      workDays: {1, 2, 3, 4, 5},
      startHour: 8,
      endHour: 18,
    );

    const physioType = EventType(
      id: 'et_physio',
      name: 'Physical Therapy Rehab',
      colorHex: '#10B981',
      workHoursConstraint: WorkHoursConstraint.workHoursOnly,
      minDuration: Duration(minutes: 45),
      maxDuration: Duration(minutes: 45),
      bufferBefore: Duration(minutes: 15),
      bufferAfter: Duration(minutes: 15),
      schedulingMode: SchedulingMode.instantAuto,
      allowedTimeWindows: [
        DayTimeWindow(dayOfWeek: DateTime.monday, startHour: 8, endHour: 12),
        DayTimeWindow(dayOfWeek: DateTime.wednesday, startHour: 8, endHour: 12),
        DayTimeWindow(dayOfWeek: DateTime.friday, startHour: 8, endHour: 12),
      ],
    );

    const patient = Entity(
      id: 'ent_alex',
      name: 'Alex Morgan',
      phone: '+15550192',
      email: 'alex@example.com',
      defaultEventTypeId: 'et_physio',
    );

    setUp(() async {
      repo = InMemorySchedulingRepository();
      calendarClient = InMemoryCalendarClient();
      syncService = CalendarSyncService(
        repository: repo,
        calendarClient: calendarClient,
      );

      await repo.saveWorkSchedule(workSchedule);
      await repo.upsertEventType(physioType);
      await repo.upsertEntity(patient);
    });

    test('Option B & A: Custom Protocol Creation + Interactive Cascade Shift Diff', () async {
      // Option B: Create a custom 6-visit protocol with 7-day weekly cadence
      final enrollment = ProtocolEnrollment(
        id: 'proto_custom_physio',
        entityId: patient.id,
        eventTypeId: physioType.id,
        protocolName: 'ACL Recovery 6-Week Plan',
        startDate: DateTime(2026, 11, 16), // Monday
        totalVisits: 6,
        cadenceDays: 7,
        toleranceWindowDays: 2,
      );

      final initialVisits = ProtocolCascadeService.generateInitialSequence(
        enrollment: enrollment,
        eventType: physioType,
        workSchedule: workSchedule,
        entity: patient,
      );

      expect(initialVisits.length, equals(6));
      await repo.upsertProtocolEnrollment(enrollment);
      await repo.upsertAppointmentsBatch(initialVisits);

      // Option A: Shift Visit #1 (index 1) by +4 days and verify dry-run & committed cascade diff
      final targetVisit = initialVisits[1];
      final searchStart = targetVisit.timeRange.start.add(const Duration(days: 4));
      final candidates = SlotFinder.findCandidateSlots(
        searchRange: TimeRange(
          start: searchStart,
          end: searchStart.add(const Duration(days: 10)),
        ),
        eventType: physioType,
        workSchedule: workSchedule,
        entity: patient,
      );
      expect(candidates, isNotEmpty);

      final dryRun = ProtocolCascadeService.recalculateCascade(
        enrollment: enrollment,
        currentAppointments: initialVisits,
        shiftedVisitIndex: 1,
        newSlot: candidates.first,
        eventType: physioType,
        workSchedule: workSchedule,
        entity: patient,
      );

      // Visits 1..5 (5 visits total) should be shifted
      expect(dryRun.shiftedVisitIndices, equals([1, 2, 3, 4, 5]));
      expect(dryRun.unresolvableVisitIndices, isEmpty);

      // Commit via repository
      final committed = await repo.rescheduleProtocolVisit(
        protocolEnrollmentId: enrollment.id,
        shiftedVisitIndex: 1,
        newSlot: candidates.first,
      );
      expect(committed.shiftedVisitIndices.length, equals(5));
    });

    test('Option C: Multi-Calendar Account Routing maps EventType to specific device account', () async {
      // Route physioType directly to existing 'cal_work_primary' account
      final routedType = physioType.copyWith(calendarMappingId: 'cal_work_primary');
      await repo.upsertEventType(routedType);

      final apt = Appointment(
        id: 'apt_routed_1',
        entityId: patient.id,
        eventTypeId: routedType.id,
        timeRange: TimeRange(
          start: DateTime(2026, 11, 16, 9, 0),
          end: DateTime(2026, 11, 16, 9, 45),
        ),
        status: AppointmentStatus.confirmed,
      );
      await repo.upsertAppointment(apt);

      final synced = await syncService.pushAppointmentToCalendar(apt);
      expect(synced.externalCalendarEventId, isNotNull);

      final workEvents = await calendarClient.retrieveEvents(
        calendarId: 'cal_work_primary',
        range: TimeRange(
          start: DateTime(2026, 11, 16, 0, 0),
          end: DateTime(2026, 11, 16, 23, 59),
        ),
      );
      expect(workEvents.length, equals(1));
      expect(workEvents.first.title, contains('Alex Morgan'));
    });

    test('Option D: Dynamic Message Templates interpolate variables and switch tones', () {
      const stringsEn = AppStrings(language: AppLanguage.en);
      final slot = TimeRange(
        start: DateTime(2026, 11, 16, 10, 0),
        end: DateTime(2026, 11, 16, 10, 45),
      );

      final clinicalMsg = stringsEn.buildConfirmationMessage(
        participantName: 'Alex Morgan',
        eventTypeName: 'Physical Therapy',
        timeRange: slot,
        visitNumber: 3,
        tone: MessageTone.clinical,
      );
      expect(clinicalMsg, contains('Dear Alex Morgan'));
      expect(clinicalMsg, contains('clinical session'));
      expect(clinicalMsg, contains('Visit #3'));

      final customMsg = stringsEn.buildConfirmationMessage(
        participantName: 'Alex Morgan',
        eventTypeName: 'Physical Therapy',
        timeRange: slot,
        visitNumber: 3,
        tone: MessageTone.custom,
        customTemplate: 'Hello {name} -> {category}{visit} on {date} [{time}]',
      );
      expect(customMsg, contains('Hello Alex Morgan -> Physical Therapy (Visit #3)'));
      expect(customMsg, contains('10:00 – 10:45'));
    });

    test('Clean Slate / Production Mode clears demo data and prevents cold-boot re-seeding', () async {
      final seeder = DemoSeedService(repo);

      await seeder.clearToCleanSlate();
      expect(await seeder.isCleanSlateEnabled(), isTrue);
      expect(await repo.getAllEventTypes(), isEmpty);
      expect(await repo.getAllEntities(), isEmpty);
      expect(await repo.getAllAppointments(), isEmpty);

      // Cold-boot seedIfEmpty should NOT re-seed while Clean Slate is active
      final didSeed = await seeder.seedIfEmpty();
      expect(didSeed, isFalse);
      expect(await repo.getAllAppointments(), isEmpty);

      // Explicit resetAndSeed restores demo data and clears the clean-slate lock
      await seeder.resetAndSeed();
      expect(await seeder.isCleanSlateEnabled(), isFalse);
      expect(await repo.getAllAppointments(), isNotEmpty);
    });
  });
}
