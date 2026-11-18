import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../data/repositories/scheduling_repository.dart';
import '../models/appointment.dart';
import '../models/entity.dart';
import '../models/event_type.dart';
import '../models/protocol_enrollment.dart';
import '../models/time_range.dart';
import '../models/work_schedule.dart';

/// Summary of records successfully restored during a backup import.
class BackupRestoreSummary {
  final int eventTypesCount;
  final int entitiesCount;
  final int protocolEnrollmentsCount;
  final int appointmentsCount;

  const BackupRestoreSummary({
    required this.eventTypesCount,
    required this.entitiesCount,
    required this.protocolEnrollmentsCount,
    required this.appointmentsCount,
  });

  @override
  String toString() =>
      'BackupRestoreSummary(eventTypes: $eventTypesCount, entities: $entitiesCount, '
      'protocols: $protocolEnrollmentsCount, appointments: $appointmentsCount)';
}

/// Service handling full database export/import (JSON) and standard calendar (.ics / RFC 5545).
class BackupService {
  const BackupService();

  // =========================================================================
  // JSON BACKUP & RESTORE
  // =========================================================================

  /// Exports the complete state of the scheduling repository to an indented JSON string.
  Future<String> exportBackupJson(SchedulingRepository repo) async {
    final workSchedule = await repo.getWorkSchedule();
    final eventTypes = await repo.getAllEventTypes();
    final entities = await repo.getAllEntities();
    final enrollments = await repo.getAllProtocolEnrollments();
    final appointments = await repo.getAllAppointments();

    final payload = {
      'version': 1,
      'app': 'Syncro',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'workSchedule': {
        'workDays': workSchedule.workDays.toList()..sort(),
        'startHour': workSchedule.startHour,
        'startMinute': workSchedule.startMinute,
        'endHour': workSchedule.endHour,
        'endMinute': workSchedule.endMinute,
      },
      'eventTypes': eventTypes.map((e) => {
        'id': e.id,
        'name': e.name,
        'code': e.effectiveCode,
        'colorHex': e.colorHex,
        'workHoursConstraint': e.workHoursConstraint.name,
        'minDurationMinutes': e.minDuration.inMinutes,
        'maxDurationMinutes': e.maxDuration.inMinutes,
        'bufferBeforeMinutes': e.bufferBefore.inMinutes,
        'bufferAfterMinutes': e.bufferAfter.inMinutes,
        'schedulingMode': e.schedulingMode.name,
        'allowedTimeWindows': e.allowedTimeWindows.map((w) => w.toJson()).toList(),
        'calendarMappingId': e.calendarMappingId,
      }).toList(),
      'entities': entities.map((e) => {
        'id': e.id,
        'name': e.name,
        'phone': e.phone,
        'email': e.email,
        'defaultEventTypeId': e.defaultEventTypeId,
        'customAvailabilityOverrides':
            e.customAvailabilityOverrides.map((w) => w.toJson()).toList(),
      }).toList(),
      'protocolEnrollments': enrollments.map((p) => {
        'id': p.id,
        'entityId': p.entityId,
        'eventTypeId': p.eventTypeId,
        'protocolName': p.protocolName,
        'startDate': p.startDate.toIso8601String(),
        'totalVisits': p.totalVisits,
        'cadenceDays': p.cadenceDays,
        'toleranceWindowDays': p.toleranceWindowDays,
      }).toList(),
      'appointments': appointments.map((a) => {
        'id': a.id,
        'entityId': a.entityId,
        'eventTypeId': a.eventTypeId,
        'start': a.timeRange.start.toIso8601String(),
        'end': a.timeRange.end.toIso8601String(),
        'status': a.status.name,
        'visitIndex': a.visitIndex,
        'protocolEnrollmentId': a.protocolEnrollmentId,
        'externalCalendarEventId': a.externalCalendarEventId,
      }).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Restores a backup from a JSON string into the repository.
  /// If [clearExisting] is true, deletes all existing database records first.
  Future<BackupRestoreSummary> importBackupJson(
    SchedulingRepository repo,
    String jsonString, {
    bool clearExisting = true,
  }) async {
    final Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected JSON object at root of backup payload');
      }
      data = decoded;
    } catch (e) {
      throw FormatException('Malformed backup JSON: $e');
    }

    if (clearExisting) {
      await repo.clearAllData();
    }

    // 1. Restore WorkSchedule
    if (data['workSchedule'] is Map<String, dynamic>) {
      final wsMap = data['workSchedule'] as Map<String, dynamic>;
      final daysList = (wsMap['workDays'] as List<dynamic>?)
              ?.map((d) => d as int)
              .toSet() ??
          {1, 2, 3, 4, 5};
      final schedule = WorkSchedule(
        workDays: daysList,
        startHour: (wsMap['startHour'] as int?) ?? 8,
        startMinute: (wsMap['startMinute'] as int?) ?? 0,
        endHour: (wsMap['endHour'] as int?) ?? 18,
        endMinute: (wsMap['endMinute'] as int?) ?? 0,
      );
      await repo.saveWorkSchedule(schedule);
    }

    // 2. Restore EventTypes
    int eventTypesCount = 0;
    if (data['eventTypes'] is List<dynamic>) {
      for (final item in data['eventTypes'] as List<dynamic>) {
        if (item is! Map<String, dynamic>) continue;
        final whConstraint = WorkHoursConstraint.values.firstWhere(
          (c) => c.name == item['workHoursConstraint'],
          orElse: () => WorkHoursConstraint.bothFlexible,
        );
        final schedMode = SchedulingMode.values.firstWhere(
          (m) => m.name == item['schedulingMode'],
          orElse: () => SchedulingMode.suggestTopRanked,
        );
        final windows = (item['allowedTimeWindows'] as List<dynamic>?)
                ?.map((w) => DayTimeWindow.fromJson(w as Map<String, dynamic>))
                .toList() ??
            [];

        final eventType = EventType(
          id: item['id'] as String,
          name: item['name'] as String,
          code: (item['code'] as String?) ?? '',
          colorHex: (item['colorHex'] as String?) ?? '#2196F3',
          workHoursConstraint: whConstraint,
          minDuration: Duration(minutes: (item['minDurationMinutes'] as int?) ?? 30),
          maxDuration: Duration(minutes: (item['maxDurationMinutes'] as int?) ?? 60),
          bufferBefore: Duration(minutes: (item['bufferBeforeMinutes'] as int?) ?? 0),
          bufferAfter: Duration(minutes: (item['bufferAfterMinutes'] as int?) ?? 0),
          schedulingMode: schedMode,
          allowedTimeWindows: windows,
          calendarMappingId: item['calendarMappingId'] as String?,
        );
        await repo.upsertEventType(eventType);
        eventTypesCount++;
      }
    }

    // 3. Restore Entities
    int entitiesCount = 0;
    if (data['entities'] is List<dynamic>) {
      for (final item in data['entities'] as List<dynamic>) {
        if (item is! Map<String, dynamic>) continue;
        final overrides = (item['customAvailabilityOverrides'] as List<dynamic>?)
                ?.map((w) => DayTimeWindow.fromJson(w as Map<String, dynamic>))
                .toList() ??
            [];

        final entity = Entity(
          id: item['id'] as String,
          name: item['name'] as String,
          phone: item['phone'] as String?,
          email: item['email'] as String?,
          defaultEventTypeId: item['defaultEventTypeId'] as String?,
          customAvailabilityOverrides: overrides,
        );
        await repo.upsertEntity(entity);
        entitiesCount++;
      }
    }

    // 4. Restore Protocol Enrollments
    int protocolsCount = 0;
    if (data['protocolEnrollments'] is List<dynamic>) {
      for (final item in data['protocolEnrollments'] as List<dynamic>) {
        if (item is! Map<String, dynamic>) continue;
        final startDate = DateTime.parse(item['startDate'] as String);
        final enrollment = ProtocolEnrollment(
          id: item['id'] as String,
          entityId: item['entityId'] as String,
          eventTypeId: item['eventTypeId'] as String,
          protocolName: item['protocolName'] as String,
          startDate: startDate,
          totalVisits: (item['totalVisits'] as int?) ?? 24,
          cadenceDays: (item['cadenceDays'] as int?) ?? 14,
          toleranceWindowDays: (item['toleranceWindowDays'] as int?) ?? 3,
        );
        await repo.upsertProtocolEnrollment(enrollment);
        protocolsCount++;
      }
    }

    // 5. Restore Appointments
    int appointmentsCount = 0;
    if (data['appointments'] is List<dynamic>) {
      final batch = <Appointment>[];
      for (final item in data['appointments'] as List<dynamic>) {
        if (item is! Map<String, dynamic>) continue;
        final status = AppointmentStatus.values.firstWhere(
          (s) => s.name == item['status'],
          orElse: () => AppointmentStatus.suggested,
        );
        final start = DateTime.parse(item['start'] as String);
        final end = DateTime.parse(item['end'] as String);

        batch.add(
          Appointment(
            id: item['id'] as String,
            entityId: item['entityId'] as String,
            eventTypeId: item['eventTypeId'] as String,
            timeRange: TimeRange(start: start, end: end),
            status: status,
            visitIndex: item['visitIndex'] as int?,
            protocolEnrollmentId: item['protocolEnrollmentId'] as String?,
            externalCalendarEventId: item['externalCalendarEventId'] as String?,
          ),
        );
      }
      if (batch.isNotEmpty) {
        await repo.upsertAppointmentsBatch(batch);
        appointmentsCount = batch.length;
      }
    }

    return BackupRestoreSummary(
      eventTypesCount: eventTypesCount,
      entitiesCount: entitiesCount,
      protocolEnrollmentsCount: protocolsCount,
      appointmentsCount: appointmentsCount,
    );
  }

  // =========================================================================
  // RFC 5545 iCalendar (.ICS) EXPORT & IMPORT
  // =========================================================================

  /// Exports all non-cancelled appointments to an RFC 5545 standard `.ics` string.
  Future<String> exportIcs(SchedulingRepository repo) async {
    final appointments = await repo.getAllAppointments();
    final entities = {for (final e in await repo.getAllEntities()) e.id: e};
    final eventTypes = {for (final t in await repo.getAllEventTypes()) t.id: t};

    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//Syncro//Calendar v1.0//EN');
    buffer.writeln('CALSCALE:GREGORIAN');
    buffer.writeln('METHOD:PUBLISH');
    buffer.writeln('X-WR-CALNAME:Syncro Schedule');
    buffer.writeln('X-WR-TIMEZONE:UTC');

    final nowStr = _formatIcsDate(DateTime.now());

    for (final apt in appointments) {
      if (apt.status == AppointmentStatus.cancelled) continue;

      final entity = entities[apt.entityId];
      final eventType = eventTypes[apt.eventTypeId];

      final participantName = entity?.name ?? apt.entityId;
      final categoryName = eventType?.name ?? apt.eventTypeId;
      final visitTag = apt.visitIndex != null ? ' (Visit #${apt.visitIndex})' : '';

      final summary = '$categoryName - $participantName$visitTag';
      final description = 'Scheduled via Syncro Engine\n'
          'Participant: $participantName\n'
          'Category: $categoryName\n'
          'Status: ${apt.status.name}\n'
          'Syncro UID: ${apt.id}';

      final icsStatus = switch (apt.status) {
        AppointmentStatus.confirmed => 'CONFIRMED',
        AppointmentStatus.completed => 'CONFIRMED',
        AppointmentStatus.suggested => 'TENTATIVE',
        AppointmentStatus.cancelled => 'CANCELLED',
      };

      buffer.writeln('BEGIN:VEVENT');
      buffer.writeln('UID:${apt.id}@syncro.app');
      buffer.writeln('DTSTAMP:$nowStr');
      buffer.writeln('DTSTART:${_formatIcsDate(apt.timeRange.start)}');
      buffer.writeln('DTEND:${_formatIcsDate(apt.timeRange.end)}');
      buffer.writeln('SUMMARY:${_escapeIcs(summary)}');
      buffer.writeln('DESCRIPTION:${_escapeIcs(description)}');
      buffer.writeln('STATUS:$icsStatus');
      buffer.writeln('END:VEVENT');
    }

    buffer.writeln('END:VCALENDAR');
    return buffer.toString();
  }

  /// Parses an RFC 5545 `.ics` string and imports parsed VEVENT components as appointments.
  Future<List<Appointment>> importIcs(
    SchedulingRepository repo,
    String icsString, {
    required String defaultEventTypeId,
    required String defaultEntityId,
  }) async {
    final lines = const LineSplitter().convert(icsString);
    final appointments = <Appointment>[];

    bool inVEvent = false;
    String? uid;
    DateTime? dtStart;
    DateTime? dtEnd;
    String? statusStr;

    for (var rawLine in lines) {
      final line = rawLine.trim();
      if (line == 'BEGIN:VEVENT') {
        inVEvent = true;
        uid = null;
        dtStart = null;
        dtEnd = null;
        statusStr = null;
        continue;
      }

      if (line == 'END:VEVENT') {
        if (inVEvent && dtStart != null && dtEnd != null) {
          final id = uid?.replaceAll('@syncro.app', '') ??
              'ics_${DateTime.now().microsecondsSinceEpoch}_${appointments.length}';
          final status = (statusStr?.toUpperCase() == 'CONFIRMED')
              ? AppointmentStatus.confirmed
              : AppointmentStatus.suggested;

          appointments.add(
            Appointment(
              id: id,
              entityId: defaultEntityId,
              eventTypeId: defaultEventTypeId,
              timeRange: TimeRange(start: dtStart, end: dtEnd),
              status: status,
            ),
          );
        }
        inVEvent = false;
        continue;
      }

      if (!inVEvent) continue;

      if (line.startsWith('UID:')) {
        uid = line.substring(4).trim();
      } else if (line.startsWith('DTSTART')) {
        final val = line.contains(':') ? line.split(':').last.trim() : '';
        dtStart = _parseIcsDate(val);
      } else if (line.startsWith('DTEND')) {
        final val = line.contains(':') ? line.split(':').last.trim() : '';
        dtEnd = _parseIcsDate(val);
      } else if (line.startsWith('STATUS:')) {
        statusStr = line.substring(7).trim();
      }
    }

    if (appointments.isNotEmpty) {
      await repo.upsertAppointmentsBatch(appointments);
    }

    return appointments;
  }

  /// Writes [content] to the application documents directory and returns the saved file.
  Future<File> saveExportToFile(String content, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    return file.writeAsString(content);
  }

  // =========================================================================
  // HELPER FORMATTERS
  // =========================================================================

  static String _formatIcsDate(DateTime dt) {
    final u = dt.toUtc();
    final y = u.year.toString().padLeft(4, '0');
    final m = u.month.toString().padLeft(2, '0');
    final d = u.day.toString().padLeft(2, '0');
    final hh = u.hour.toString().padLeft(2, '0');
    final mm = u.minute.toString().padLeft(2, '0');
    final ss = u.second.toString().padLeft(2, '0');
    return '$y$m$d' 'T' '$hh$mm$ss' 'Z';
  }

  static DateTime? _parseIcsDate(String raw) {
    if (raw.isEmpty) return null;
    try {
      // Formats:
      // 1. 20261115T140000Z
      // 2. 20261115T140000
      // 3. 20261115
      final clean = raw.replaceAll('Z', '');
      if (clean.length == 15 && clean.contains('T')) {
        final y = int.parse(clean.substring(0, 4));
        final m = int.parse(clean.substring(4, 6));
        final d = int.parse(clean.substring(6, 8));
        final hh = int.parse(clean.substring(9, 11));
        final mm = int.parse(clean.substring(11, 13));
        final ss = int.parse(clean.substring(13, 15));
        if (raw.endsWith('Z')) {
          return DateTime.utc(y, m, d, hh, mm, ss).toLocal();
        }
        return DateTime(y, m, d, hh, mm, ss);
      } else if (clean.length == 8) {
        final y = int.parse(clean.substring(0, 4));
        final m = int.parse(clean.substring(4, 6));
        final d = int.parse(clean.substring(6, 8));
        return DateTime(y, m, d);
      }
    } catch (_) {}
    return null;
  }

  static String _escapeIcs(String text) {
    return text
        .replaceAll('\\', r'\\')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,')
        .replaceAll('\n', r'\n');
  }
}
