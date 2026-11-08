import 'dart:async';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../domain/models/appointment.dart';
import '../../domain/models/entity.dart';
import '../../domain/models/event_type.dart';
import '../../domain/models/protocol_enrollment.dart';
import '../../domain/models/time_range.dart';
import '../../domain/models/work_schedule.dart';
import 'tables.dart';

/// Reactive Drift SQLite database for Syncro.
///
/// Extends Drift's [GeneratedDatabase] and uses parameterized SQL + reactive
/// table change notifications so the project compiles and runs out-of-the-box
/// even before `build_runner` code generation is invoked.
class AppDatabase extends GeneratedDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  final StreamController<String> _tableUpdateBroadcaster =
      StreamController<String>.broadcast();

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'syncro_db');
  }

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await _createSchema();
        },
      );

  /// Creates the 5 core relational tables and performance indexes for interval queries.
  Future<void> _createSchema() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS work_schedules (
        id TEXT PRIMARY KEY NOT NULL DEFAULT 'default',
        work_days_json TEXT NOT NULL DEFAULT '[1,2,3,4,5]',
        start_hour INTEGER NOT NULL DEFAULT 8,
        start_minute INTEGER NOT NULL DEFAULT 0,
        end_hour INTEGER NOT NULL DEFAULT 18,
        end_minute INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS event_types (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        color_hex TEXT NOT NULL DEFAULT '#2196F3',
        work_hours_constraint TEXT NOT NULL DEFAULT 'bothFlexible',
        min_duration_minutes INTEGER NOT NULL,
        max_duration_minutes INTEGER NOT NULL,
        buffer_before_minutes INTEGER NOT NULL DEFAULT 0,
        buffer_after_minutes INTEGER NOT NULL DEFAULT 0,
        scheduling_mode TEXT NOT NULL DEFAULT 'suggestTopRanked',
        allowed_time_windows_json TEXT NOT NULL DEFAULT '[]',
        calendar_mapping_id TEXT
      )
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS entities (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        default_event_type_id TEXT REFERENCES event_types(id),
        custom_availability_overrides_json TEXT NOT NULL DEFAULT '[]'
      )
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS protocol_enrollments (
        id TEXT PRIMARY KEY NOT NULL,
        entity_id TEXT NOT NULL REFERENCES entities(id),
        event_type_id TEXT NOT NULL REFERENCES event_types(id),
        protocol_name TEXT NOT NULL,
        start_date_epoch_ms INTEGER NOT NULL,
        total_visits INTEGER NOT NULL DEFAULT 24,
        cadence_days INTEGER NOT NULL DEFAULT 14,
        tolerance_window_days INTEGER NOT NULL DEFAULT 3
      )
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS appointments (
        id TEXT PRIMARY KEY NOT NULL,
        entity_id TEXT NOT NULL REFERENCES entities(id),
        event_type_id TEXT NOT NULL REFERENCES event_types(id),
        start_epoch_ms INTEGER NOT NULL,
        end_epoch_ms INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'suggested',
        visit_index INTEGER,
        protocol_enrollment_id TEXT REFERENCES protocol_enrollments(id),
        external_calendar_event_id TEXT
      )
    ''');

    // Index for fast O(log N) interval range lookups
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_appointments_time_range
      ON appointments (start_epoch_ms, end_epoch_ms)
    ''');

    // Index for protocol roadmap queries ordered by visit_index
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_appointments_protocol
      ON appointments (protocol_enrollment_id, visit_index)
    ''');
  }

  void _emitTableChange(String tableName) {
    if (!_tableUpdateBroadcaster.isClosed) {
      _tableUpdateBroadcaster.add(tableName);
    }
    notifyUpdates({TableUpdate(tableName)});
  }

  Stream<T> _watchTable<T>(
    Set<String> watchedTables,
    Future<T> Function() fetcher,
  ) async* {
    yield await fetcher();
    await for (final updatedTable in _tableUpdateBroadcaster.stream) {
      if (watchedTables.contains(updatedTable) || updatedTable == '*') {
        yield await fetcher();
      }
    }
  }

  // ===========================================================================
  // 1. WORK SCHEDULE DAO OPERATIONS
  // ===========================================================================

  Future<WorkSchedule> getWorkSchedule() async {
    final rows = await customSelect(
      'SELECT * FROM work_schedules WHERE id = ? LIMIT 1',
      variables: [Variable.withString('default')],
    ).get();

    if (rows.isEmpty) {
      return const WorkSchedule();
    }
    return _mapRowToWorkSchedule(rows.first);
  }

  Stream<WorkSchedule> watchWorkSchedule() {
    return _watchTable({'work_schedules'}, getWorkSchedule);
  }

  Future<void> saveWorkSchedule(WorkSchedule schedule) async {
    await customStatement(
      '''
      INSERT INTO work_schedules (id, work_days_json, start_hour, start_minute, end_hour, end_minute)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        work_days_json = excluded.work_days_json,
        start_hour = excluded.start_hour,
        start_minute = excluded.start_minute,
        end_hour = excluded.end_hour,
        end_minute = excluded.end_minute
      ''',
      [
        'default',
        WorkDaysSetConverter.encode(schedule.workDays),
        schedule.startHour,
        schedule.startMinute,
        schedule.endHour,
        schedule.endMinute,
      ],
    );
    _emitTableChange('work_schedules');
  }

  WorkSchedule _mapRowToWorkSchedule(QueryRow row) {
    return WorkSchedule(
      workDays: WorkDaysSetConverter.decode(row.read<String>('work_days_json')),
      startHour: row.read<int>('start_hour'),
      startMinute: row.read<int>('start_minute'),
      endHour: row.read<int>('end_hour'),
      endMinute: row.read<int>('end_minute'),
    );
  }

  // ===========================================================================
  // 2. EVENT TYPES DAO OPERATIONS
  // ===========================================================================

  Future<List<EventType>> getAllEventTypes() async {
    final rows = await customSelect(
      'SELECT * FROM event_types ORDER BY name ASC',
    ).get();
    return rows.map(_mapRowToEventType).toList();
  }

  Future<EventType?> getEventTypeById(String id) async {
    final rows = await customSelect(
      'SELECT * FROM event_types WHERE id = ? LIMIT 1',
      variables: [Variable.withString(id)],
    ).get();
    if (rows.isEmpty) return null;
    return _mapRowToEventType(rows.first);
  }

  Stream<List<EventType>> watchAllEventTypes() {
    return _watchTable({'event_types'}, getAllEventTypes);
  }

  Future<void> upsertEventType(EventType eventType) async {
    await customStatement(
      '''
      INSERT INTO event_types (
        id, name, color_hex, work_hours_constraint,
        min_duration_minutes, max_duration_minutes,
        buffer_before_minutes, buffer_after_minutes,
        scheduling_mode, allowed_time_windows_json, calendar_mapping_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        color_hex = excluded.color_hex,
        work_hours_constraint = excluded.work_hours_constraint,
        min_duration_minutes = excluded.min_duration_minutes,
        max_duration_minutes = excluded.max_duration_minutes,
        buffer_before_minutes = excluded.buffer_before_minutes,
        buffer_after_minutes = excluded.buffer_after_minutes,
        scheduling_mode = excluded.scheduling_mode,
        allowed_time_windows_json = excluded.allowed_time_windows_json,
        calendar_mapping_id = excluded.calendar_mapping_id
      ''',
      [
        eventType.id,
        eventType.name,
        eventType.colorHex,
        eventType.workHoursConstraint.name,
        eventType.minDuration.inMinutes,
        eventType.maxDuration.inMinutes,
        eventType.bufferBefore.inMinutes,
        eventType.bufferAfter.inMinutes,
        eventType.schedulingMode.name,
        DayTimeWindowListConverter.encode(eventType.allowedTimeWindows),
        eventType.calendarMappingId,
      ],
    );
    _emitTableChange('event_types');
  }

  EventType _mapRowToEventType(QueryRow row) {
    final constraintName = row.read<String>('work_hours_constraint');
    final modeName = row.read<String>('scheduling_mode');

    return EventType(
      id: row.read<String>('id'),
      name: row.read<String>('name'),
      colorHex: row.read<String>('color_hex'),
      workHoursConstraint: WorkHoursConstraint.values.firstWhere(
        (e) => e.name == constraintName,
        orElse: () => WorkHoursConstraint.bothFlexible,
      ),
      minDuration: Duration(minutes: row.read<int>('min_duration_minutes')),
      maxDuration: Duration(minutes: row.read<int>('max_duration_minutes')),
      bufferBefore: Duration(minutes: row.read<int>('buffer_before_minutes')),
      bufferAfter: Duration(minutes: row.read<int>('buffer_after_minutes')),
      schedulingMode: SchedulingMode.values.firstWhere(
        (e) => e.name == modeName,
        orElse: () => SchedulingMode.suggestTopRanked,
      ),
      allowedTimeWindows: DayTimeWindowListConverter.decode(
        row.read<String>('allowed_time_windows_json'),
      ),
      calendarMappingId: row.readNullable<String>('calendar_mapping_id'),
    );
  }

  // ===========================================================================
  // 3. ENTITIES DAO OPERATIONS
  // ===========================================================================

  Future<List<Entity>> getAllEntities() async {
    final rows = await customSelect(
      'SELECT * FROM entities ORDER BY name ASC',
    ).get();
    return rows.map(_mapRowToEntity).toList();
  }

  Future<Entity?> getEntityById(String id) async {
    final rows = await customSelect(
      'SELECT * FROM entities WHERE id = ? LIMIT 1',
      variables: [Variable.withString(id)],
    ).get();
    if (rows.isEmpty) return null;
    return _mapRowToEntity(rows.first);
  }

  Stream<List<Entity>> watchAllEntities() {
    return _watchTable({'entities'}, getAllEntities);
  }

  Future<void> upsertEntity(Entity entity) async {
    await customStatement(
      '''
      INSERT INTO entities (
        id, name, phone, email, default_event_type_id, custom_availability_overrides_json
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        phone = excluded.phone,
        email = excluded.email,
        default_event_type_id = excluded.default_event_type_id,
        custom_availability_overrides_json = excluded.custom_availability_overrides_json
      ''',
      [
        entity.id,
        entity.name,
        entity.phone,
        entity.email,
        entity.defaultEventTypeId,
        DayTimeWindowListConverter.encode(entity.customAvailabilityOverrides),
      ],
    );
    _emitTableChange('entities');
  }

  Entity _mapRowToEntity(QueryRow row) {
    return Entity(
      id: row.read<String>('id'),
      name: row.read<String>('name'),
      phone: row.readNullable<String>('phone'),
      email: row.readNullable<String>('email'),
      defaultEventTypeId: row.readNullable<String>('default_event_type_id'),
      customAvailabilityOverrides: DayTimeWindowListConverter.decode(
        row.read<String>('custom_availability_overrides_json'),
      ),
    );
  }

  // ===========================================================================
  // 4. PROTOCOL ENROLLMENTS DAO OPERATIONS
  // ===========================================================================

  Future<List<ProtocolEnrollment>> getAllProtocolEnrollments() async {
    final rows = await customSelect(
      'SELECT * FROM protocol_enrollments ORDER BY start_date_epoch_ms DESC',
    ).get();
    return rows.map(_mapRowToProtocolEnrollment).toList();
  }

  Future<ProtocolEnrollment?> getProtocolEnrollmentById(String id) async {
    final rows = await customSelect(
      'SELECT * FROM protocol_enrollments WHERE id = ? LIMIT 1',
      variables: [Variable.withString(id)],
    ).get();
    if (rows.isEmpty) return null;
    return _mapRowToProtocolEnrollment(rows.first);
  }

  Stream<List<ProtocolEnrollment>> watchAllProtocolEnrollments() {
    return _watchTable({'protocol_enrollments'}, getAllProtocolEnrollments);
  }

  Future<void> upsertProtocolEnrollment(ProtocolEnrollment enrollment) async {
    await customStatement(
      '''
      INSERT INTO protocol_enrollments (
        id, entity_id, event_type_id, protocol_name,
        start_date_epoch_ms, total_visits, cadence_days, tolerance_window_days
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        entity_id = excluded.entity_id,
        event_type_id = excluded.event_type_id,
        protocol_name = excluded.protocol_name,
        start_date_epoch_ms = excluded.start_date_epoch_ms,
        total_visits = excluded.total_visits,
        cadence_days = excluded.cadence_days,
        tolerance_window_days = excluded.tolerance_window_days
      ''',
      [
        enrollment.id,
        enrollment.entityId,
        enrollment.eventTypeId,
        enrollment.protocolName,
        enrollment.startDate.millisecondsSinceEpoch,
        enrollment.totalVisits,
        enrollment.cadenceDays,
        enrollment.toleranceWindowDays,
      ],
    );
    _emitTableChange('protocol_enrollments');
  }

  ProtocolEnrollment _mapRowToProtocolEnrollment(QueryRow row) {
    return ProtocolEnrollment(
      id: row.read<String>('id'),
      entityId: row.read<String>('entity_id'),
      eventTypeId: row.read<String>('event_type_id'),
      protocolName: row.read<String>('protocol_name'),
      startDate: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('start_date_epoch_ms'),
      ),
      totalVisits: row.read<int>('total_visits'),
      cadenceDays: row.read<int>('cadence_days'),
      toleranceWindowDays: row.read<int>('tolerance_window_days'),
    );
  }

  // ===========================================================================
  // 5. APPOINTMENTS DAO OPERATIONS
  // ===========================================================================

  Future<List<Appointment>> getAllAppointments() async {
    final rows = await customSelect(
      'SELECT * FROM appointments ORDER BY start_epoch_ms ASC',
    ).get();
    return rows.map(_mapRowToAppointment).toList();
  }

  /// Queries all appointments overlapping with [range] using half-open interval logic:
  /// `appointment.start < range.end AND range.start < appointment.end`
  Future<List<Appointment>> getAppointmentsInRange(TimeRange range) async {
    final rows = await customSelect(
      '''
      SELECT * FROM appointments
      WHERE start_epoch_ms < ? AND end_epoch_ms > ?
      ORDER BY start_epoch_ms ASC
      ''',
      variables: [
        Variable.withInt(range.end.millisecondsSinceEpoch),
        Variable.withInt(range.start.millisecondsSinceEpoch),
      ],
    ).get();
    return rows.map(_mapRowToAppointment).toList();
  }

  Future<List<Appointment>> getAppointmentsForProtocol(
    String protocolEnrollmentId,
  ) async {
    final rows = await customSelect(
      '''
      SELECT * FROM appointments
      WHERE protocol_enrollment_id = ?
      ORDER BY visit_index ASC, start_epoch_ms ASC
      ''',
      variables: [Variable.withString(protocolEnrollmentId)],
    ).get();
    return rows.map(_mapRowToAppointment).toList();
  }

  Stream<List<Appointment>> watchAllAppointments() {
    return _watchTable({'appointments'}, getAllAppointments);
  }

  Future<void> upsertAppointment(Appointment appointment) async {
    await _insertOrUpdateAppointmentRow(appointment);
    _emitTableChange('appointments');
  }

  /// Atomically persists a batch of appointments (e.g., 24 cascaded protocol visits)
  /// in a single SQLite transaction.
  Future<void> upsertAppointmentsBatch(List<Appointment> appointments) async {
    await transaction(() async {
      for (final apt in appointments) {
        await _insertOrUpdateAppointmentRow(apt);
      }
    });
    _emitTableChange('appointments');
  }

  Future<void> _insertOrUpdateAppointmentRow(Appointment appointment) async {
    await customStatement(
      '''
      INSERT INTO appointments (
        id, entity_id, event_type_id, start_epoch_ms, end_epoch_ms,
        status, visit_index, protocol_enrollment_id, external_calendar_event_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        entity_id = excluded.entity_id,
        event_type_id = excluded.event_type_id,
        start_epoch_ms = excluded.start_epoch_ms,
        end_epoch_ms = excluded.end_epoch_ms,
        status = excluded.status,
        visit_index = excluded.visit_index,
        protocol_enrollment_id = excluded.protocol_enrollment_id,
        external_calendar_event_id = excluded.external_calendar_event_id
      ''',
      [
        appointment.id,
        appointment.entityId,
        appointment.eventTypeId,
        appointment.timeRange.start.millisecondsSinceEpoch,
        appointment.timeRange.end.millisecondsSinceEpoch,
        appointment.status.name,
        appointment.visitIndex,
        appointment.protocolEnrollmentId,
        appointment.externalCalendarEventId,
      ],
    );
  }

  Future<void> deleteAppointment(String id) async {
    await customStatement(
      'DELETE FROM appointments WHERE id = ?',
      [id],
    );
    _emitTableChange('appointments');
  }

  Appointment _mapRowToAppointment(QueryRow row) {
    final statusName = row.read<String>('status');
    return Appointment(
      id: row.read<String>('id'),
      entityId: row.read<String>('entity_id'),
      eventTypeId: row.read<String>('event_type_id'),
      timeRange: TimeRange(
        start: DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('start_epoch_ms'),
        ),
        end: DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('end_epoch_ms'),
        ),
      ),
      status: AppointmentStatus.values.firstWhere(
        (e) => e.name == statusName,
        orElse: () => AppointmentStatus.suggested,
      ),
      visitIndex: row.readNullable<int>('visit_index'),
      protocolEnrollmentId: row.readNullable<String>('protocol_enrollment_id'),
      externalCalendarEventId:
          row.readNullable<String>('external_calendar_event_id'),
    );
  }

  // ===========================================================================
  // 6. DATABASE MAINTENANCE & RESET
  // ===========================================================================

  /// Clears all rows across all tables in dependency order.
  Future<void> clearAllData() async {
    await transaction(() async {
      await customStatement('DELETE FROM appointments');
      await customStatement('DELETE FROM protocol_enrollments');
      await customStatement('DELETE FROM entities');
      await customStatement('DELETE FROM event_types');
      await customStatement('DELETE FROM work_schedules');
    });
    _emitTableChange('*');
  }

  @override
  Future<void> close() async {
    await _tableUpdateBroadcaster.close();
    await super.close();
  }
}
