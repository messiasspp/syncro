import 'package:flutter_test/flutter_test.dart';
import 'package:syncro/features/scheduling/data/calendar/calendar_client.dart';
import 'package:syncro/features/scheduling/data/repositories/scheduling_repository.dart';
import 'package:syncro/features/scheduling/domain/models/appointment.dart';
import 'package:syncro/features/scheduling/domain/models/entity.dart';
import 'package:syncro/features/scheduling/domain/models/event_type.dart';
import 'package:syncro/features/scheduling/domain/models/external_calendar.dart';
import 'package:syncro/features/scheduling/domain/models/time_range.dart';
import 'package:syncro/features/scheduling/domain/models/work_schedule.dart';
import 'package:syncro/features/scheduling/domain/services/calendar_sync_service.dart';

void main() {
  group('Option 3: External Calendar Conflict Detection & Auto-Resolution', () {
    late InMemorySchedulingRepository repo;
    late InMemoryCalendarClient client;
    late CalendarSyncService syncService;

    setUp(() async {
      repo = InMemorySchedulingRepository();
      client = InMemoryCalendarClient();
      syncService = CalendarSyncService(
        repository: repo,
        calendarClient: client,
      );

      await repo.saveWorkSchedule(
        const WorkSchedule(
          workDays: {1, 2, 3, 4, 5},
          startHour: 8,
          endHour: 18,
        ),
      );

      await repo.upsertEventType(
        const EventType(
          id: 'clinical_study',
          name: 'Mounjaro Clinical Study',
          workHoursConstraint: WorkHoursConstraint.workHoursOnly,
          minDuration: Duration(minutes: 45),
          maxDuration: Duration(minutes: 45),
          bufferBefore: Duration(minutes: 15),
          bufferAfter: Duration(minutes: 15),
          schedulingMode: SchedulingMode.instantAuto,
          allowedTimeWindows: [
            DayTimeWindow(
              dayOfWeek: 1, // Monday
              startHour: 8,
              endHour: 12,
            ),
            DayTimeWindow(
              dayOfWeek: 3, // Wednesday
              startHour: 8,
              endHour: 12,
            ),
          ],
        ),
      );

      await repo.upsertEntity(
        const Entity(
          id: 'patient_101',
          name: 'Patient 101',
          defaultEventTypeId: 'clinical_study',
        ),
      );
    });

    test('detectConflicts finds overlapping external calendar event', () async {
      // Base date: Monday, Nov 16, 2026
      final baseDate = DateTime(2026, 11, 16);

      // Syncro appointment at 09:00 - 09:45
      final apt = Appointment(
        id: 'apt_test_1',
        entityId: 'patient_101',
        eventTypeId: 'clinical_study',
        timeRange: TimeRange(
          start: DateTime(baseDate.year, baseDate.month, baseDate.day, 9, 0),
          end: DateTime(baseDate.year, baseDate.month, baseDate.day, 9, 45),
        ),
        status: AppointmentStatus.confirmed,
      );
      await repo.upsertAppointment(apt);

      // External personal event at 09:30 - 10:30 (overlaps with appointment 09:00-09:45)
      await client.createOrUpdateEvent(
        ExternalCalendarEvent(
          calendarId: 'cal_personal_primary',
          title: 'Dentist Appointment',
          timeRange: TimeRange(
            start: DateTime(baseDate.year, baseDate.month, baseDate.day, 9, 30),
            end: DateTime(baseDate.year, baseDate.month, baseDate.day, 10, 30),
          ),
        ),
      );

      final conflicts = await syncService.detectConflicts();

      expect(conflicts.containsKey('apt_test_1'), isTrue);
      final report = conflicts['apt_test_1']!;
      expect(report.appointment.id, equals('apt_test_1'));
      expect(report.conflictingEvent.title, equals('Dentist Appointment'));
    });

    test('adjacent non-overlapping events do not trigger conflict', () async {
      final baseDate = DateTime(2026, 11, 16);

      // Syncro appointment at 09:00 - 10:00
      final apt = Appointment(
        id: 'apt_test_2',
        entityId: 'patient_101',
        eventTypeId: 'clinical_study',
        timeRange: TimeRange(
          start: DateTime(baseDate.year, baseDate.month, baseDate.day, 9, 0),
          end: DateTime(baseDate.year, baseDate.month, baseDate.day, 10, 0),
        ),
        status: AppointmentStatus.confirmed,
      );
      await repo.upsertAppointment(apt);

      // External event immediately adjacent at 10:00 - 11:00
      await client.createOrUpdateEvent(
        ExternalCalendarEvent(
          calendarId: 'cal_personal_primary',
          title: 'Team Standup',
          timeRange: TimeRange(
            start: DateTime(baseDate.year, baseDate.month, baseDate.day, 10, 0),
            end: DateTime(baseDate.year, baseDate.month, baseDate.day, 11, 0),
          ),
        ),
      );

      final conflicts = await syncService.detectConflicts();
      expect(conflicts.containsKey('apt_test_2'), isFalse);
    });

    test('suggestConflictResolutions returns alternative collision-free candidate slots', () async {
      final baseDate = DateTime(2026, 11, 16); // Monday

      final apt = Appointment(
        id: 'apt_test_3',
        entityId: 'patient_101',
        eventTypeId: 'clinical_study',
        timeRange: TimeRange(
          start: DateTime(baseDate.year, baseDate.month, baseDate.day, 8, 30),
          end: DateTime(baseDate.year, baseDate.month, baseDate.day, 9, 15),
        ),
        status: AppointmentStatus.confirmed,
      );
      await repo.upsertAppointment(apt);

      final externalEvent = ExternalCalendarEvent(
        calendarId: 'cal_personal_primary',
        title: 'Doctor Visit',
        timeRange: TimeRange(
          start: DateTime(baseDate.year, baseDate.month, baseDate.day, 8, 0),
          end: DateTime(baseDate.year, baseDate.month, baseDate.day, 9, 0),
        ),
      );
      await client.createOrUpdateEvent(externalEvent);

      final conflicts = await syncService.detectConflicts();
      expect(conflicts.containsKey('apt_test_3'), isTrue);

      final suggestions = await syncService.suggestConflictResolutions(
        conflicts['apt_test_3']!.appointment,
        maxSuggestions: 3,
      );

      expect(suggestions, isNotEmpty);
      expect(suggestions.length, lessThanOrEqualTo(3));

      // None of the suggestions should overlap with the external event
      for (final slot in suggestions) {
        expect(slot.overlaps(externalEvent.timeRange), isFalse);
      }
    });

    test('autoResolveConflict updates appointment to alternative slot and clears conflict', () async {
      final baseDate = DateTime(2026, 11, 16); // Monday

      final apt = Appointment(
        id: 'apt_test_4',
        entityId: 'patient_101',
        eventTypeId: 'clinical_study',
        timeRange: TimeRange(
          start: DateTime(baseDate.year, baseDate.month, baseDate.day, 8, 0),
          end: DateTime(baseDate.year, baseDate.month, baseDate.day, 8, 45),
        ),
        status: AppointmentStatus.confirmed,
      );
      await repo.upsertAppointment(apt);

      final externalEvent = ExternalCalendarEvent(
        calendarId: 'cal_personal_primary',
        title: 'Emergency Review',
        timeRange: TimeRange(
          start: DateTime(baseDate.year, baseDate.month, baseDate.day, 8, 0),
          end: DateTime(baseDate.year, baseDate.month, baseDate.day, 9, 0),
        ),
      );
      await client.createOrUpdateEvent(externalEvent);

      final conflictsBefore = await syncService.detectConflicts();
      expect(conflictsBefore.containsKey('apt_test_4'), isTrue);

      final suggestions = await syncService.suggestConflictResolutions(
        conflictsBefore['apt_test_4']!.appointment,
        maxSuggestions: 1,
      );
      expect(suggestions, isNotEmpty);

      final resolved = await syncService.autoResolveConflict(
        appointment: conflictsBefore['apt_test_4']!.appointment,
        newSlot: suggestions.first,
      );

      expect(resolved.timeRange.overlaps(externalEvent.timeRange), isFalse);

      // Verify repository was updated
      final updatedApt = (await repo.getAllAppointments())
          .firstWhere((a) => a.id == 'apt_test_4');
      expect(updatedApt.timeRange, equals(resolved.timeRange));

      // Conflicts should now be empty for this appointment
      final conflictsAfter = await syncService.detectConflicts();
      expect(conflictsAfter.containsKey('apt_test_4'), isFalse);
    });
  });
}
