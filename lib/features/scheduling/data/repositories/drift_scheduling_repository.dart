import 'dart:async';

import '../../domain/models/appointment.dart';
import '../../domain/models/entity.dart';
import '../../domain/models/event_type.dart';
import '../../domain/models/protocol_enrollment.dart';
import '../../domain/models/time_range.dart';
import '../../domain/models/work_schedule.dart';
import '../../domain/services/protocol_cascade_service.dart';
import '../local/app_database.dart';
import 'scheduling_repository.dart';

/// Production implementation of [SchedulingRepository] backed by Drift SQLite ([AppDatabase]).
class DriftSchedulingRepository implements SchedulingRepository {
  final AppDatabase _db;

  const DriftSchedulingRepository(this._db);

  @override
  Future<WorkSchedule> getWorkSchedule() => _db.getWorkSchedule();

  @override
  Stream<WorkSchedule> watchWorkSchedule() => _db.watchWorkSchedule();

  @override
  Future<void> saveWorkSchedule(WorkSchedule schedule) =>
      _db.saveWorkSchedule(schedule);

  @override
  Future<List<EventType>> getAllEventTypes() => _db.getAllEventTypes();

  @override
  Future<EventType?> getEventTypeById(String id) => _db.getEventTypeById(id);

  @override
  Stream<List<EventType>> watchAllEventTypes() => _db.watchAllEventTypes();

  @override
  Future<void> upsertEventType(EventType eventType) =>
      _db.upsertEventType(eventType);

  @override
  Future<List<Entity>> getAllEntities() => _db.getAllEntities();

  @override
  Future<Entity?> getEntityById(String id) => _db.getEntityById(id);

  @override
  Stream<List<Entity>> watchAllEntities() => _db.watchAllEntities();

  @override
  Future<void> upsertEntity(Entity entity) => _db.upsertEntity(entity);

  @override
  Future<List<ProtocolEnrollment>> getAllProtocolEnrollments() =>
      _db.getAllProtocolEnrollments();

  @override
  Future<ProtocolEnrollment?> getProtocolEnrollmentById(String id) =>
      _db.getProtocolEnrollmentById(id);

  @override
  Stream<List<ProtocolEnrollment>> watchAllProtocolEnrollments() =>
      _db.watchAllProtocolEnrollments();

  @override
  Future<void> upsertProtocolEnrollment(ProtocolEnrollment enrollment) =>
      _db.upsertProtocolEnrollment(enrollment);

  @override
  Future<List<Appointment>> getAllAppointments() => _db.getAllAppointments();

  @override
  Future<List<Appointment>> getAppointmentsInRange(TimeRange range) =>
      _db.getAppointmentsInRange(range);

  @override
  Future<List<Appointment>> getAppointmentsForProtocol(
    String protocolEnrollmentId,
  ) =>
      _db.getAppointmentsForProtocol(protocolEnrollmentId);

  @override
  Stream<List<Appointment>> watchAllAppointments() =>
      _db.watchAllAppointments();

  @override
  Future<void> upsertAppointment(Appointment appointment) =>
      _db.upsertAppointment(appointment);

  @override
  Future<void> upsertAppointmentsBatch(List<Appointment> appointments) =>
      _db.upsertAppointmentsBatch(appointments);

  @override
  Future<void> deleteAppointment(String id) => _db.deleteAppointment(id);

  @override
  Future<CascadeShiftResult> rescheduleProtocolVisit({
    required String protocolEnrollmentId,
    required int shiftedVisitIndex,
    required TimeRange newSlot,
  }) async {
    final enrollment = await getProtocolEnrollmentById(protocolEnrollmentId);
    if (enrollment == null) {
      throw StateError('ProtocolEnrollment not found: $protocolEnrollmentId');
    }

    final eventType = await getEventTypeById(enrollment.eventTypeId);
    if (eventType == null) {
      throw StateError('EventType not found: ${enrollment.eventTypeId}');
    }

    final entity = await getEntityById(enrollment.entityId);
    if (entity == null) {
      throw StateError('Entity not found: ${enrollment.entityId}');
    }

    final workSchedule = await getWorkSchedule();
    final allAppointments = await getAllAppointments();

    final protocolAppointments = allAppointments
        .where((a) => a.protocolEnrollmentId == protocolEnrollmentId)
        .toList();

    final externalBusySlots = allAppointments
        .where((a) =>
            a.protocolEnrollmentId != protocolEnrollmentId &&
            a.status != AppointmentStatus.cancelled)
        .map((a) => a.timeRange)
        .toList();

    final cascadeResult = ProtocolCascadeService.recalculateCascade(
      enrollment: enrollment,
      currentAppointments: protocolAppointments,
      shiftedVisitIndex: shiftedVisitIndex,
      newSlot: newSlot,
      eventType: eventType,
      workSchedule: workSchedule,
      entity: entity,
      externalBusySlots: externalBusySlots,
    );

    await upsertAppointmentsBatch(cascadeResult.updatedAppointments);
    return cascadeResult;
  }

  @override
  Future<void> clearAllData() => _db.clearAllData();
}
