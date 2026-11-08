import 'package:flutter_test/flutter_test.dart';
import 'package:syncro/features/scheduling/data/local/tables.dart';
import 'package:syncro/features/scheduling/data/repositories/scheduling_repository.dart';
import 'package:syncro/features/scheduling/data/seed/demo_seed_service.dart';
import 'package:syncro/features/scheduling/domain/models/event_type.dart';
import 'package:syncro/features/scheduling/domain/models/time_range.dart';

void main() {
  group('SQLite TypeConverters', () {
    test('WorkDaysSetConverter encodes and decodes Set<int> deterministically', () {
      const converter = WorkDaysSetConverter();
      final days = {DateTime.friday, DateTime.monday, DateTime.wednesday};

      final encoded = converter.toSql(days);
      expect(encoded, '[1,3,5]');

      final decoded = converter.fromSql(encoded);
      expect(decoded, days);
    });

    test('DayTimeWindowListConverter round-trips List<DayTimeWindow>', () {
      const converter = DayTimeWindowListConverter();
      const windows = [
        DayTimeWindow(
          dayOfWeek: DateTime.thursday,
          startHour: 19,
          startMinute: 0,
          endHour: 22,
          endMinute: 0,
        ),
        DayTimeWindow(
          dayOfWeek: DateTime.saturday,
          startHour: 12,
          startMinute: 30,
          endHour: 18,
          endMinute: 0,
        ),
      ];

      final jsonStr = converter.toSql(windows);
      final restored = converter.fromSql(jsonStr);

      expect(restored, windows);
    });
  });

  group('DemoSeedService & SchedulingRepository', () {
    late InMemorySchedulingRepository repository;
    late DemoSeedService seeder;

    setUp(() {
      repository = InMemorySchedulingRepository();
      seeder = DemoSeedService(repository);
    });

    test('seedIfEmpty populates Friends Zone and Mounjaro Study collision-free', () async {
      final didSeed = await seeder.seedIfEmpty(
        referenceDate: DateTime(2026, 10, 19),
      );
      expect(didSeed, true);

      // Subsequent call to seedIfEmpty is a no-op
      final secondSeed = await seeder.seedIfEmpty(
        referenceDate: DateTime(2026, 10, 19),
      );
      expect(secondSeed, false);

      // Verify EventTypes
      final eventTypes = await repository.getAllEventTypes();
      expect(eventTypes.length, 2);

      // Verify Entities (Mendy, Patient 101, Patient 102)
      final entities = await repository.getAllEntities();
      expect(entities.length, 3);

      // Verify Protocol Enrollments
      final enrollments = await repository.getAllProtocolEnrollments();
      expect(enrollments.length, 2);

      // Verify 24 visits for Patient 101 + 24 visits for Patient 102 + 1 hangout for Mendy = 49 appointments
      final allAppointments = await repository.getAllAppointments();
      expect(allAppointments.length, 49);

      // Verify Patient 102's visits strictly follow the Wednesday 10:00 - 12:00 override
      final p102Visits = await repository.getAppointmentsForProtocol(
        DemoSeedService.patient102EnrollmentId,
      );
      expect(p102Visits.length, 24);
      for (final visit in p102Visits) {
        expect(visit.timeRange.start.weekday, DateTime.wednesday);
        expect(visit.timeRange.start.hour >= 10, true);
        expect(visit.timeRange.end.hour <= 12, true);
      }

      // Verify zero pairwise overlap across all 49 seeded appointments
      for (int i = 0; i < allAppointments.length - 1; i++) {
        final current = allAppointments[i];
        final next = allAppointments[i + 1];
        expect(
          current.timeRange.overlaps(next.timeRange),
          false,
          reason:
              'Appointment ${current.id} (${current.timeRange}) collided with ${next.id} (${next.timeRange})',
        );
      }
    });

    test('rescheduleProtocolVisit cascades and persists downstream visits atomically', () async {
      await seeder.resetAndSeed(referenceDate: DateTime(2026, 10, 19));

      // Shift Patient 101's Visit 1 (originally Monday Nov 2, 2026) to Wednesday Nov 4, 2026 08:00 - 08:45
      final newVisit1Slot = TimeRange(
        start: DateTime(2026, 11, 4, 8, 0),
        end: DateTime(2026, 11, 4, 8, 45),
      );

      final result = await repository.rescheduleProtocolVisit(
        protocolEnrollmentId: DemoSeedService.patient101EnrollmentId,
        shiftedVisitIndex: 1,
        newSlot: newVisit1Slot,
      );

      expect(result.shiftedVisitIndices.contains(1), true);
      expect(result.unresolvableVisitIndices.isEmpty, true);

      final persistedVisits = await repository.getAppointmentsForProtocol(
        DemoSeedService.patient101EnrollmentId,
      );
      expect(persistedVisits[1].timeRange, newVisit1Slot);
    });
  });
}
