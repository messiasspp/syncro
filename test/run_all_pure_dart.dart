import 'dart:io';
import 'package:syncro/features/scheduling/data/calendar/calendar_client.dart';
import 'package:syncro/features/scheduling/data/repositories/scheduling_repository.dart';
import 'package:syncro/features/scheduling/data/seed/demo_seed_service.dart';
import 'package:syncro/features/scheduling/domain/models/entity.dart';
import 'package:syncro/features/scheduling/domain/models/event_type.dart';
import 'package:syncro/features/scheduling/domain/models/external_calendar.dart';
import 'package:syncro/features/scheduling/domain/models/protocol_enrollment.dart';
import 'package:syncro/features/scheduling/domain/models/time_range.dart';
import 'package:syncro/features/scheduling/domain/models/work_schedule.dart';
import 'package:syncro/features/scheduling/domain/services/calendar_sync_service.dart';
import 'package:syncro/features/scheduling/domain/services/interval_math.dart';
import 'package:syncro/features/scheduling/domain/services/protocol_cascade_service.dart';
import 'package:syncro/features/scheduling/domain/services/slot_finder.dart';

Future<void> main() async {
  stdout.writeln('========================================');
  stdout.writeln('🚀 Running Pure Dart Scheduling Engine Tests');
  stdout.writeln('========================================\n');

  int passed = 0;
  int failed = 0;

  Future<void> testCase(String name, Future<void> Function() testFn) async {
    try {
      await testFn();
      stdout.writeln('  ✅ PASS: $name');
      passed++;
    } catch (e, st) {
      stdout.writeln('  ❌ FAIL: $name\n     $e\n$st');
      failed++;
    }
  }

  // --- INTERVAL MATH TESTS ---
  stdout.writeln('📦 [Suite 1: IntervalMath]');

  await testCase('IntervalMath: merge overlapping and adjacent ranges', () async {
    final base = DateTime(2026, 10, 19, 10, 0);
    final r1 = TimeRange(start: base, end: base.add(const Duration(minutes: 60)));
    final r2 = TimeRange(
      start: base.add(const Duration(minutes: 30)),
      end: base.add(const Duration(minutes: 90)),
    );
    final r3 = TimeRange(
      start: base.add(const Duration(minutes: 120)),
      end: base.add(const Duration(minutes: 180)),
    );

    final merged = IntervalMath.mergeOverlapping([r1, r2, r3]);
    assert(merged.length == 2, 'Should merge into 2 disjoint intervals');
    assert(merged[0].start == base && merged[0].end == base.add(const Duration(minutes: 90)));
  });

  await testCase('IntervalMath: subtract busy blocks with sweepline', () async {
    final day = DateTime(2026, 10, 19);
    final available = [
      TimeRange(
        start: DateTime(day.year, day.month, day.day, 9, 0),
        end: DateTime(day.year, day.month, day.day, 17, 0),
      ),
    ];
    final busy = [
      TimeRange(
        start: DateTime(day.year, day.month, day.day, 11, 0),
        end: DateTime(day.year, day.month, day.day, 13, 0),
      ),
    ];

    final free = IntervalMath.subtractIntervals(available: available, busy: busy);
    assert(free.length == 2, 'Should carve into 2 free windows');
    assert(free[0].start == DateTime(day.year, day.month, day.day, 9, 0));
    assert(free[0].end == DateTime(day.year, day.month, day.day, 11, 0));
    assert(free[1].start == DateTime(day.year, day.month, day.day, 13, 0));
    assert(free[1].end == DateTime(day.year, day.month, day.day, 17, 0));
  });

  // --- SCENARIO 1: FRIENDS ZONE ---
  stdout.writeln('\n📦 [Suite 2: Scenario 1 - Friends Zone (Personal / Off-Hours)]');

  const standardWorkSchedule = WorkSchedule(
    workDays: {
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    },
    startHour: 8,
    endHour: 18,
  );

  const friendsZoneType = EventType(
    id: 'type_friends',
    name: 'Friends Zone',
    workHoursConstraint: WorkHoursConstraint.outsideWorkHours,
    minDuration: Duration(hours: 2),
    maxDuration: Duration(hours: 3),
    allowedTimeWindows: [
      DayTimeWindow(dayOfWeek: DateTime.thursday, startHour: 19, endHour: 22),
      DayTimeWindow(dayOfWeek: DateTime.saturday, startHour: 12, endHour: 18),
    ],
  );

  const mendy = Entity(
    id: 'entity_mendy',
    name: 'Mendy',
    defaultEventTypeId: 'type_friends',
  );

  await testCase('Friends Zone: falls back to Saturday when Thursday is blocked', () async {
    final searchRange = TimeRange(
      start: DateTime(2026, 10, 19, 0, 0),
      end: DateTime(2026, 10, 25, 23, 59),
    );
    // Block Thursday 19:30 - 21:00
    final busy = [
      TimeRange(
        start: DateTime(2026, 10, 22, 19, 30),
        end: DateTime(2026, 10, 22, 21, 0),
      ),
    ];

    final slots = SlotFinder.findCandidateSlots(
      searchRange: searchRange,
      eventType: friendsZoneType,
      workSchedule: standardWorkSchedule,
      entity: mendy,
      busySlots: busy,
      slotStep: const Duration(minutes: 30),
    );

    assert(slots.isNotEmpty, 'Should find slots on Saturday');
    for (final slot in slots) {
      assert(slot.start.weekday == DateTime.saturday, 'Slots must be on Saturday');
      assert(slot.start.hour >= 12 && slot.end.hour <= 18, 'Must be in 12:00-18:00');
    }
  });

  // --- SCENARIO 2: MOUNJARO CLINICAL STUDY ---
  stdout.writeln('\n📦 [Suite 3: Scenario 2 - Mounjaro Clinical Protocol]');

  const mounjaroType = EventType(
    id: 'type_mounjaro',
    name: 'Mounjaro Clinical Study',
    workHoursConstraint: WorkHoursConstraint.workHoursOnly,
    minDuration: Duration(minutes: 45),
    maxDuration: Duration(minutes: 45),
    bufferBefore: Duration(minutes: 15),
    bufferAfter: Duration(minutes: 15),
    allowedTimeWindows: [
      DayTimeWindow(dayOfWeek: DateTime.monday, startHour: 8, endHour: 12),
      DayTimeWindow(dayOfWeek: DateTime.wednesday, startHour: 8, endHour: 12),
    ],
  );

  const patient101 = Entity(
    id: 'patient_101',
    name: 'Patient 101',
    defaultEventTypeId: 'type_mounjaro',
  );

  await testCase('Mounjaro Study: generates initial 24-visit roadmap with 14-day cadence', () async {
    final enrollment = ProtocolEnrollment(
      id: 'enrollment_p101',
      entityId: patient101.id,
      eventTypeId: mounjaroType.id,
      protocolName: 'Mounjaro Protocol',
      startDate: DateTime(2026, 10, 19),
      totalVisits: 24,
      cadenceDays: 14,
    );

    final visits = ProtocolCascadeService.generateInitialSequence(
      enrollment: enrollment,
      eventType: mounjaroType,
      workSchedule: standardWorkSchedule,
      entity: patient101,
    );

    assert(visits.length == 24, 'Must generate exactly 24 visits');
    assert(visits.first.visitIndex == 0, 'First visit index is 0');
    assert(visits.last.visitIndex == 23, 'Last visit index is 23');
  });

  await testCase('Mounjaro Study: cascading shift updates downstream visits', () async {
    final enrollment = ProtocolEnrollment(
      id: 'enrollment_p101',
      entityId: patient101.id,
      eventTypeId: mounjaroType.id,
      protocolName: 'Mounjaro Protocol',
      startDate: DateTime(2026, 10, 19),
      totalVisits: 6,
      cadenceDays: 14,
    );

    final initialVisits = ProtocolCascadeService.generateInitialSequence(
      enrollment: enrollment,
      eventType: mounjaroType,
      workSchedule: standardWorkSchedule,
      entity: patient101,
    );

    final delayedSlot = TimeRange(
      start: DateTime(2026, 11, 4, 9, 0),
      end: DateTime(2026, 11, 4, 9, 45),
    );

    final result = ProtocolCascadeService.recalculateCascade(
      enrollment: enrollment,
      currentAppointments: initialVisits,
      shiftedVisitIndex: 1,
      newSlot: delayedSlot,
      eventType: mounjaroType,
      workSchedule: standardWorkSchedule,
      entity: patient101,
    );

    assert(result.shiftedVisitIndices.contains(1), 'Visit 1 shifted');
    assert(result.shiftedVisitIndices.contains(2), 'Visit 2 cascaded');
    assert(result.updatedAppointments[1].timeRange == delayedSlot, 'Visit 1 time updated');
  });

  // --- SUITE 4: REPOSITORY & SEED SERVICE ---
  stdout.writeln('\n📦 [Suite 4: Phase 3 - Repository & DemoSeedService]');

  await testCase('DemoSeedService: populates 2 event types, 3 entities, 2 enrollments, 49 non-colliding appointments', () async {
    final repository = InMemorySchedulingRepository();
    final seeder = DemoSeedService(repository);

    final seeded = await seeder.seedIfEmpty(referenceDate: DateTime(2026, 10, 19));
    assert(seeded == true, 'Should seed when repository is empty');

    final appointments = await repository.getAllAppointments();
    assert(appointments.length == 49, 'Should generate 49 total appointments (24 + 24 + 1)');

    for (int i = 0; i < appointments.length - 1; i++) {
      assert(
        !appointments[i].timeRange.overlaps(appointments[i + 1].timeRange),
        'Appointments must never overlap',
      );
    }
  });

  // --- SUITE 5: CALENDAR SYNC SERVICE ---
  stdout.writeln('\n📦 [Suite 5: Phase 4 - CalendarSyncService & Sub-Calendars]');

  await testCase('CalendarSyncService: provisions dedicated sub-calendars and merges external busy slots', () async {
    final repository = InMemorySchedulingRepository();
    final calendarClient = InMemoryCalendarClient();
    final seeder = DemoSeedService(repository);
    final syncService = CalendarSyncService(
      repository: repository,
      calendarClient: calendarClient,
    );

    await seeder.resetAndSeed(referenceDate: DateTime(2026, 10, 19));

    final syncResult = await syncService.syncAll();
    assert(syncResult.isSuccess, 'Sync should succeed without errors');
    assert(syncResult.createdCalendarsCount == 2, 'Should create 2 dedicated sub-calendars');
    assert(syncResult.pushedAppointmentsCount == 48, 'Should push 48 Mounjaro visits');

    // Add external busy event and verify fetchMergedBusySlots includes it
    await calendarClient.createOrUpdateEvent(
      ExternalCalendarEvent(
        calendarId: 'cal_personal_primary',
        title: 'External Conflict',
        timeRange: TimeRange(
          start: DateTime(2026, 10, 22, 19, 0),
          end: DateTime(2026, 10, 22, 21, 0),
        ),
      ),
    );

    final mergedBusy = await syncService.fetchMergedBusySlots(
      TimeRange(
        start: DateTime(2026, 10, 19, 0, 0),
        end: DateTime(2026, 10, 25, 23, 59),
      ),
    );
    assert(mergedBusy.isNotEmpty, 'Should return merged internal and external busy intervals');
  });

  stdout.writeln('\n========================================');
  stdout.writeln('🏁 Test Summary: $passed Passed, $failed Failed');
  stdout.writeln('========================================');

  if (failed > 0) {
    exit(1);
  }
}
