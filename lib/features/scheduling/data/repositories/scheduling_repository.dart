import 'dart:async';

import '../../domain/models/appointment.dart';
import '../../domain/models/entity.dart';
import '../../domain/models/event_type.dart';
import '../../domain/models/protocol_enrollment.dart';
import '../../domain/models/time_range.dart';
import '../../domain/models/work_schedule.dart';
import '../../domain/services/protocol_cascade_service.dart';

/// Abstract contract for reading, watching, and mutating scheduling data.
abstract class SchedulingRepository {
  // Work Schedule
  Future<WorkSchedule> getWorkSchedule();
  Stream<WorkSchedule> watchWorkSchedule();
  Future<void> saveWorkSchedule(WorkSchedule schedule);

  // Event Types
  Future<List<EventType>> getAllEventTypes();
  Future<EventType?> getEventTypeById(String id);
  Stream<List<EventType>> watchAllEventTypes();
  Future<void> upsertEventType(EventType eventType);

  // Entities
  Future<List<Entity>> getAllEntities();
  Future<Entity?> getEntityById(String id);
  Stream<List<Entity>> watchAllEntities();
  Future<void> upsertEntity(Entity entity);

  // Protocol Enrollments
  Future<List<ProtocolEnrollment>> getAllProtocolEnrollments();
  Future<ProtocolEnrollment?> getProtocolEnrollmentById(String id);
  Stream<List<ProtocolEnrollment>> watchAllProtocolEnrollments();
  Future<void> upsertProtocolEnrollment(ProtocolEnrollment enrollment);

  // Appointments
  Future<List<Appointment>> getAllAppointments();
  Future<List<Appointment>> getAppointmentsInRange(TimeRange range);
  Future<List<Appointment>> getAppointmentsForProtocol(
    String protocolEnrollmentId,
  );
  Stream<List<Appointment>> watchAllAppointments();
  Future<void> upsertAppointment(Appointment appointment);
  Future<void> upsertAppointmentsBatch(List<Appointment> appointments);
  Future<void> deleteAppointment(String id);

  /// Reschedules visit [shiftedVisitIndex] of [protocolEnrollmentId] to [newSlot],
  /// automatically cascading downstream visits and persisting the updated sequence.
  Future<CascadeShiftResult> rescheduleProtocolVisit({
    required String protocolEnrollmentId,
    required int shiftedVisitIndex,
    required TimeRange newSlot,
  });

  // Maintenance
  Future<void> clearAllData();
}

/// Fast, reactive in-memory implementation of [SchedulingRepository] for unit tests
/// and pure-Dart verification without native SQLite dynamic library dependencies.
class InMemorySchedulingRepository implements SchedulingRepository {
  WorkSchedule _workSchedule = const WorkSchedule();
  final Map<String, EventType> _eventTypes = {};
  final Map<String, Entity> _entities = {};
  final Map<String, ProtocolEnrollment> _enrollments = {};
  final Map<String, Appointment> _appointments = {};

  final StreamController<void> _changeController =
      StreamController<void>.broadcast();

  void _notify() {
    if (!_changeController.isClosed) {
      _changeController.add(null);
    }
  }

  Stream<T> _watch<T>(Future<T> Function() getter) async* {
    yield await getter();
    await for (final _ in _changeController.stream) {
      yield await getter();
    }
  }

  @override
  Future<WorkSchedule> getWorkSchedule() async => _workSchedule;

  @override
  Stream<WorkSchedule> watchWorkSchedule() => _watch(getWorkSchedule);

  @override
  Future<void> saveWorkSchedule(WorkSchedule schedule) async {
    _workSchedule = schedule;
    _notify();
  }

  @override
  Future<List<EventType>> getAllEventTypes() async {
    final list = _eventTypes.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  @override
  Future<EventType?> getEventTypeById(String id) async => _eventTypes[id];

  @override
  Stream<List<EventType>> watchAllEventTypes() => _watch(getAllEventTypes);

  @override
  Future<void> upsertEventType(EventType eventType) async {
    _eventTypes[eventType.id] = eventType;
    _notify();
  }

  @override
  Future<List<Entity>> getAllEntities() async {
    final list = _entities.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  @override
  Future<Entity?> getEntityById(String id) async => _entities[id];

  @override
  Stream<List<Entity>> watchAllEntities() => _watch(getAllEntities);

  @override
  Future<void> upsertEntity(Entity entity) async {
    _entities[entity.id] = entity;
    _notify();
  }

  @override
  Future<List<ProtocolEnrollment>> getAllProtocolEnrollments() async {
    final list = _enrollments.values.toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    return list;
  }

  @override
  Future<ProtocolEnrollment?> getProtocolEnrollmentById(String id) async =>
      _enrollments[id];

  @override
  Stream<List<ProtocolEnrollment>> watchAllProtocolEnrollments() =>
      _watch(getAllProtocolEnrollments);

  @override
  Future<void> upsertProtocolEnrollment(ProtocolEnrollment enrollment) async {
    _enrollments[enrollment.id] = enrollment;
    _notify();
  }

  @override
  Future<List<Appointment>> getAllAppointments() async {
    final list = _appointments.values.toList()
      ..sort((a, b) => a.timeRange.compareTo(b.timeRange));
    return list;
  }

  @override
  Future<List<Appointment>> getAppointmentsInRange(TimeRange range) async {
    final all = await getAllAppointments();
    return all.where((a) => a.timeRange.overlaps(range)).toList();
  }

  @override
  Future<List<Appointment>> getAppointmentsForProtocol(
    String protocolEnrollmentId,
  ) async {
    final all = await getAllAppointments();
    return all
        .where((a) => a.protocolEnrollmentId == protocolEnrollmentId)
        .toList()
      ..sort((a, b) => (a.visitIndex ?? 0).compareTo(b.visitIndex ?? 0));
  }

  @override
  Stream<List<Appointment>> watchAllAppointments() => _watch(getAllAppointments);

  @override
  Future<void> upsertAppointment(Appointment appointment) async {
    _appointments[appointment.id] = appointment;
    _notify();
  }

  @override
  Future<void> upsertAppointmentsBatch(List<Appointment> appointments) async {
    for (final apt in appointments) {
      _appointments[apt.id] = apt;
    }
    _notify();
  }

  @override
  Future<void> deleteAppointment(String id) async {
    _appointments.remove(id);
    _notify();
  }

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
  Future<void> clearAllData() async {
    _workSchedule = const WorkSchedule();
    _eventTypes.clear();
    _entities.clear();
    _enrollments.clear();
    _appointments.clear();
    _notify();
  }
}
