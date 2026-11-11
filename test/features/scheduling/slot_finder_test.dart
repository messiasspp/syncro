import 'package:flutter_test/flutter_test.dart';
import 'package:syncro/features/scheduling/domain/models/entity.dart';
import 'package:syncro/features/scheduling/domain/models/event_type.dart';
import 'package:syncro/features/scheduling/domain/models/time_range.dart';
import 'package:syncro/features/scheduling/domain/models/work_schedule.dart';
import 'package:syncro/features/scheduling/domain/services/slot_finder.dart';

void main() {
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

  group('Scenario 1: Friends Zone (Personal / Outside Work Hours)', () {
    // Rule: Outside work hours, Thursday evenings (19:00 - 22:00) or Saturdays (12:00 - 18:00)
    const friendsZoneType = EventType(
      id: 'type_friends',
      name: 'Friends Zone',
      workHoursConstraint: WorkHoursConstraint.outsideWorkHours,
      minDuration: Duration(hours: 2),
      maxDuration: Duration(hours: 3),
      allowedTimeWindows: [
        DayTimeWindow(
          dayOfWeek: DateTime.thursday,
          startHour: 19,
          endHour: 22,
        ),
        DayTimeWindow(
          dayOfWeek: DateTime.saturday,
          startHour: 12,
          endHour: 18,
        ),
      ],
    );

    const mendy = Entity(
      id: 'entity_mendy',
      name: 'Mendy',
      defaultEventTypeId: 'type_friends',
    );

    test('finds slots only on Thursday evening and Saturday within allowed windows', () {
      // Oct 19, 2026 is Monday, search through Sunday Oct 25, 2026
      final searchRange = TimeRange(
        start: DateTime(2026, 10, 19, 0, 0),
        end: DateTime(2026, 10, 25, 23, 59),
      );

      // Existing busy event on Thursday 19:30 - 21:00 (movie night)
      final busySlots = [
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
        busySlots: busySlots,
        slotStep: const Duration(minutes: 30),
      );

      // Since Thursday 19:00-22:00 had a busy event from 19:30 to 21:00,
      // no 2-hour continuous block fits on Thursday!
      // All valid 2-hour slots must fall on Saturday (Oct 24, 2026) between 12:00 and 18:00.
      expect(slots.isNotEmpty, true);
      for (final slot in slots) {
        expect(slot.start.weekday, DateTime.saturday);
        expect(slot.start.hour >= 12, true);
        expect(slot.end.hour <= 18, true);
        expect(slot.duration, const Duration(hours: 2));
      }
    });
  });

  group('Scenario 2: Clinical Research - Mounjaro Study (Professional / Work Hours + Buffers)', () {
    // Rule: Work hours only, Mon & Wed (08:00 - 12:00), 45m duration + 15m pre & post buffer
    const mounjaroType = EventType(
      id: 'type_mounjaro',
      name: 'Mounjaro Clinical Study',
      workHoursConstraint: WorkHoursConstraint.workHoursOnly,
      minDuration: Duration(minutes: 45),
      maxDuration: Duration(minutes: 45),
      bufferBefore: Duration(minutes: 15),
      bufferAfter: Duration(minutes: 15),
      allowedTimeWindows: [
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

    // Patient 101: standard participant
    const patient101 = Entity(
      id: 'patient_101',
      name: 'Patient 101',
      defaultEventTypeId: 'type_mounjaro',
    );

    // Patient 102: custom override - can only attend Wednesdays after 10:00 AM
    const patient102 = Entity(
      id: 'patient_102',
      name: 'Patient 102',
      defaultEventTypeId: 'type_mounjaro',
      customAvailabilityOverrides: [
        DayTimeWindow(
          dayOfWeek: DateTime.wednesday,
          startHour: 10,
          endHour: 12,
        ),
      ],
    );

    test('enforces buffers and prevents collisions with existing busy appointments', () {
      final searchRange = TimeRange(
        start: DateTime(2026, 10, 19, 0, 0), // Monday
        end: DateTime(2026, 10, 21, 23, 59), // Wednesday
      );

      // Existing appointment on Monday from 09:00 to 10:00
      final busySlots = [
        TimeRange(
          start: DateTime(2026, 10, 19, 9, 0),
          end: DateTime(2026, 10, 19, 10, 0),
        ),
      ];

      final slots = SlotFinder.findCandidateSlots(
        searchRange: searchRange,
        eventType: mounjaroType,
        workSchedule: standardWorkSchedule,
        entity: patient101,
        busySlots: busySlots,
        slotStep: const Duration(minutes: 15),
      );

      // Any slot before the busy event must end by 09:00 - 15m buffer = 08:45.
      // 08:00 - 08:45 is a valid 45-min slot!
      final earlySlot = slots.firstWhere((s) => s.start.hour == 8 && s.start.minute == 0);
      expect(earlySlot.end, DateTime(2026, 10, 19, 8, 45));

      // Any slot after the busy event cannot start before 10:00 + 15m buffer = 10:15.
      final noCollisionWithBuffer = slots.every((s) {
        if (s.start.weekday != DateTime.monday) return true;
        // Either ends by 08:45 OR starts at or after 10:15
        final endsBeforeBuffer = !s.end.isAfter(DateTime(2026, 10, 19, 8, 45));
        final startsAfterBuffer = !s.start.isBefore(DateTime(2026, 10, 19, 10, 15));
        return endsBeforeBuffer || startsAfterBuffer;
      });
      expect(noCollisionWithBuffer, true);
    });

    test('respects Patient 102 custom availability override (Wednesdays 10:00 - 12:00 only)', () {
      final searchRange = TimeRange(
        start: DateTime(2026, 10, 19, 0, 0), // Monday
        end: DateTime(2026, 10, 21, 23, 59), // Wednesday
      );

      final slots = SlotFinder.findCandidateSlots(
        searchRange: searchRange,
        eventType: mounjaroType,
        workSchedule: standardWorkSchedule,
        entity: patient102,
      );

      expect(slots.isNotEmpty, true);
      // All candidate slots for Patient 102 must be strictly on Wednesday between 10:00 and 12:00
      for (final slot in slots) {
        expect(slot.start.weekday, DateTime.wednesday);
        expect(slot.start.hour >= 10, true);
        expect(slot.end.hour <= 12, true);
      }
    });
  });
}
