import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncro/features/scheduling/data/repositories/scheduling_repository.dart';
import 'package:syncro/features/scheduling/domain/models/appointment.dart';
import 'package:syncro/features/scheduling/domain/models/entity.dart';
import 'package:syncro/features/scheduling/domain/models/event_type.dart';
import 'package:syncro/features/scheduling/domain/models/protocol_enrollment.dart';
import 'package:syncro/features/scheduling/domain/models/time_range.dart';
import 'package:syncro/features/scheduling/domain/models/work_schedule.dart';
import 'package:syncro/features/scheduling/domain/services/backup_service.dart';

void main() {
  group('Option 4: BackupService (JSON & RFC 5545 .ics)', () {
    late InMemorySchedulingRepository repo;
    const backupService = BackupService();

    setUp(() async {
      repo = InMemorySchedulingRepository();

      await repo.saveWorkSchedule(
        const WorkSchedule(
          workDays: {1, 2, 3, 4, 5},
          startHour: 9,
          startMinute: 0,
          endHour: 17,
          endMinute: 30,
        ),
      );

      await repo.upsertEventType(
        const EventType(
          id: 'clinical_study',
          name: 'Mounjaro Clinical Study',
          colorHex: '#10B981',
          workHoursConstraint: WorkHoursConstraint.workHoursOnly,
          minDuration: Duration(minutes: 45),
          maxDuration: Duration(minutes: 45),
          bufferBefore: Duration(minutes: 15),
          bufferAfter: Duration(minutes: 15),
          schedulingMode: SchedulingMode.instantAuto,
          allowedTimeWindows: [
            DayTimeWindow(dayOfWeek: 1, startHour: 8, endHour: 12),
          ],
        ),
      );

      await repo.upsertEntity(
        const Entity(
          id: 'patient_101',
          name: 'Patient 101',
          email: 'p101@example.com',
          phone: '+15551234567',
          defaultEventTypeId: 'clinical_study',
        ),
      );

      await repo.upsertProtocolEnrollment(
        ProtocolEnrollment(
          id: 'protocol_1',
          entityId: 'patient_101',
          eventTypeId: 'clinical_study',
          protocolName: 'Mounjaro 1-Year Trial',
          startDate: DateTime.utc(2026, 11, 16, 9, 0),
          totalVisits: 24,
          cadenceDays: 14,
          toleranceWindowDays: 3,
        ),
      );

      await repo.upsertAppointment(
        Appointment(
          id: 'apt_1',
          entityId: 'patient_101',
          eventTypeId: 'clinical_study',
          timeRange: TimeRange(
            start: DateTime.utc(2026, 11, 16, 9, 0),
            end: DateTime.utc(2026, 11, 16, 9, 45),
          ),
          status: AppointmentStatus.confirmed,
          visitIndex: 1,
          protocolEnrollmentId: 'protocol_1',
        ),
      );
    });

    test('exportBackupJson produces valid JSON containing all entities and metadata', () async {
      final jsonStr = await backupService.exportBackupJson(repo);
      expect(jsonStr, isNotEmpty);

      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(decoded['app'], equals('Syncro'));
      expect(decoded['version'], equals(1));
      expect(decoded['workSchedule']['startHour'], equals(9));
      expect(decoded['workSchedule']['endMinute'], equals(30));

      final eventTypes = decoded['eventTypes'] as List<dynamic>;
      expect(eventTypes.length, equals(1));
      expect(eventTypes.first['id'], equals('clinical_study'));
      expect(eventTypes.first['colorHex'], equals('#10B981'));

      final entities = decoded['entities'] as List<dynamic>;
      expect(entities.length, equals(1));
      expect(entities.first['id'], equals('patient_101'));
      expect(entities.first['email'], equals('p101@example.com'));

      final protocols = decoded['protocolEnrollments'] as List<dynamic>;
      expect(protocols.length, equals(1));
      expect(protocols.first['protocolName'], equals('Mounjaro 1-Year Trial'));

      final appointments = decoded['appointments'] as List<dynamic>;
      expect(appointments.length, equals(1));
      expect(appointments.first['id'], equals('apt_1'));
      expect(appointments.first['status'], equals('confirmed'));
    });

    test('importBackupJson restores into a blank repository accurately', () async {
      final jsonStr = await backupService.exportBackupJson(repo);

      // Create a new blank repo
      final freshRepo = InMemorySchedulingRepository();
      expect(await freshRepo.getAllEventTypes(), isEmpty);
      expect(await freshRepo.getAllEntities(), isEmpty);
      expect(await freshRepo.getAllAppointments(), isEmpty);

      final summary = await backupService.importBackupJson(freshRepo, jsonStr);

      expect(summary.eventTypesCount, equals(1));
      expect(summary.entitiesCount, equals(1));
      expect(summary.protocolEnrollmentsCount, equals(1));
      expect(summary.appointmentsCount, equals(1));

      // Validate restored records
      final restoredWs = await freshRepo.getWorkSchedule();
      expect(restoredWs.startHour, equals(9));
      expect(restoredWs.endMinute, equals(30));

      final restoredTypes = await freshRepo.getAllEventTypes();
      expect(restoredTypes.first.name, equals('Mounjaro Clinical Study'));

      final restoredEntities = await freshRepo.getAllEntities();
      expect(restoredEntities.first.name, equals('Patient 101'));

      final restoredApts = await freshRepo.getAllAppointments();
      expect(restoredApts.first.id, equals('apt_1'));
      expect(restoredApts.first.visitIndex, equals(1));
      expect(restoredApts.first.status, equals(AppointmentStatus.confirmed));
    });

    test('importBackupJson throws FormatException on invalid payload', () async {
      final freshRepo = InMemorySchedulingRepository();
      expect(
        () => backupService.importBackupJson(freshRepo, 'not a json string'),
        throwsFormatException,
      );
    });

    test('exportIcs generates valid RFC 5545 VCALENDAR string', () async {
      final ics = await backupService.exportIcs(repo);

      expect(ics.contains('BEGIN:VCALENDAR'), isTrue);
      expect(ics.contains('VERSION:2.0'), isTrue);
      expect(ics.contains('PRODID:-//Syncro//Calendar v1.0//EN'), isTrue);
      expect(ics.contains('BEGIN:VEVENT'), isTrue);
      expect(ics.contains('UID:apt_1@syncro.app'), isTrue);
      expect(ics.contains('DTSTART:20261116T090000Z'), isTrue);
      expect(ics.contains('DTEND:20261116T094500Z'), isTrue);
      expect(ics.contains('SUMMARY:Mounjaro Clinical Study - Patient 101 (Visit #1)'), isTrue);
      expect(ics.contains('STATUS:CONFIRMED'), isTrue);
      expect(ics.contains('END:VEVENT'), isTrue);
      expect(ics.contains('END:VCALENDAR'), isTrue);
    });

    test('importIcs parses VEVENT entries into new appointments', () async {
      const sampleIcs = '''
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//External//Calendar//EN
BEGIN:VEVENT
UID:sample_external_001@example.com
DTSTART:20261201T140000Z
DTEND:20261201T150000Z
SUMMARY:Consultation Session
STATUS:CONFIRMED
END:VEVENT
END:VCALENDAR
''';

      final freshRepo = InMemorySchedulingRepository();
      final imported = await backupService.importIcs(
        freshRepo,
        sampleIcs,
        defaultEventTypeId: 'clinical_study',
        defaultEntityId: 'patient_101',
      );

      expect(imported.length, equals(1));
      expect(imported.first.id, equals('sample_external_001@example.com'));
      expect(imported.first.timeRange.start.hour, isNotNull);
      expect(imported.first.status, equals(AppointmentStatus.confirmed));

      final inRepo = await freshRepo.getAllAppointments();
      expect(inRepo.length, equals(1));
    });
  });
}
