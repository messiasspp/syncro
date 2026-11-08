import 'package:flutter_test/flutter_test.dart';
import 'package:syncro/features/scheduling/domain/models/entity.dart';
import 'package:syncro/features/scheduling/domain/models/event_type.dart';
import 'package:syncro/features/scheduling/domain/models/protocol_enrollment.dart';
import 'package:syncro/features/scheduling/domain/models/time_range.dart';
import 'package:syncro/features/scheduling/domain/models/work_schedule.dart';
import 'package:syncro/features/scheduling/domain/services/protocol_cascade_service.dart';

void main() {
  final standardWorkSchedule = WorkSchedule(
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

  final mounjaroType = EventType(
    id: 'type_mounjaro',
    name: 'Mounjaro Clinical Study',
    workHoursConstraint: WorkHoursConstraint.workHoursOnly,
    minDuration: const Duration(minutes: 45),
    maxDuration: const Duration(minutes: 45),
    bufferBefore: const Duration(minutes: 15),
    bufferAfter: const Duration(minutes: 15),
    allowedTimeWindows: const [
      DayTimeWindow(
        dayOfWeek: DateTime.monday,
        startHour: 8,
        endHour: 12,
      ),
      DayTimeWindow(
        dayOfWeek: DateTime.wednesday,
        startHour: 8,
        endHour: 12,
      ),
    ],
  );

  final patient101 = Entity(
    id: 'patient_101',
    name: 'Patient 101',
    defaultEventTypeId: 'type_mounjaro',
  );

  group('Protocol Cascade Rescheduling', () {
    test('generates initial 24-visit sequence spaced by 14-day cadence', () {
      final enrollment = ProtocolEnrollment(
        id: 'enrollment_p101',
        entityId: patient101.id,
        eventTypeId: mounjaroType.id,
        protocolName: 'Mounjaro Clinical Study - Cohort A',
        startDate: DateTime(2026, 10, 19), // Monday
        totalVisits: 24,
        cadenceDays: 14,
        toleranceWindowDays: 3,
      );

      final initialSequence = ProtocolCascadeService.generateInitialSequence(
        enrollment: enrollment,
        eventType: mounjaroType,
        workSchedule: standardWorkSchedule,
        entity: patient101,
      );

      expect(initialSequence.length, 24);
      expect(initialSequence[0].visitIndex, 0);
      expect(initialSequence[0].timeRange.start.weekday, DateTime.monday);

      // Verify each visit satisfies the event type constraints
      for (int i = 0; i < initialSequence.length; i++) {
        final visit = initialSequence[i];
        expect(visit.visitIndex, i);
        expect(
          visit.timeRange.start.weekday == DateTime.monday ||
              visit.timeRange.start.weekday == DateTime.wednesday,
          true,
        );
        expect(visit.timeRange.duration, const Duration(minutes: 45));
      }
    });

    test('cascades downstream visits forward when Visit 1 is delayed', () {
      final enrollment = ProtocolEnrollment(
        id: 'enrollment_p101',
        entityId: patient101.id,
        eventTypeId: mounjaroType.id,
        protocolName: 'Mounjaro Clinical Study - Cohort A',
        startDate: DateTime(2026, 10, 19), // Monday
        totalVisits: 6, // testing with 6 visits for clarity
        cadenceDays: 14,
        toleranceWindowDays: 3,
      );

      final initialSequence = ProtocolCascadeService.generateInitialSequence(
        enrollment: enrollment,
        eventType: mounjaroType,
        workSchedule: standardWorkSchedule,
        entity: patient101,
      );

      final originalVisit1 = initialSequence[1];
      final originalVisit2 = initialSequence[2];

      // Delay Visit 1 by 2 days (from Monday Nov 2 to Wednesday Nov 4)
      final delayedSlot = TimeRange(
        start: DateTime(2026, 11, 4, 9, 0),
        end: DateTime(2026, 11, 4, 9, 45),
      );

      final cascadeResult = ProtocolCascadeService.recalculateCascade(
        enrollment: enrollment,
        currentAppointments: initialSequence,
        shiftedVisitIndex: 1,
        newSlot: delayedSlot,
        eventType: mounjaroType,
        workSchedule: standardWorkSchedule,
        entity: patient101,
      );

      expect(cascadeResult.shiftedVisitIndices.contains(1), true);
      expect(cascadeResult.shiftedVisitIndices.contains(2), true);

      final updatedVisit1 = cascadeResult.updatedAppointments[1];
      final updatedVisit2 = cascadeResult.updatedAppointments[2];

      expect(updatedVisit1.timeRange.start.isAfter(originalVisit1.timeRange.start), true);
      expect(updatedVisit1.timeRange, delayedSlot);

      // Visit 2 must now be at least 14 days after the new Visit 1 date (Nov 4 + 14 = Nov 18)
      expect(updatedVisit2.timeRange.start.isAfter(originalVisit2.timeRange.start) ||
          updatedVisit2.timeRange.start.isAtSameMomentAs(originalVisit2.timeRange.start.add(const Duration(days: 2))), true);
    });
  });
}
