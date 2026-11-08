import '../../domain/models/appointment.dart';
import '../../domain/models/entity.dart';
import '../../domain/models/event_type.dart';
import '../../domain/models/protocol_enrollment.dart';
import '../../domain/models/time_range.dart';
import '../../domain/models/work_schedule.dart';
import '../../domain/services/protocol_cascade_service.dart';
import '../../domain/services/slot_finder.dart';
import '../repositories/scheduling_repository.dart';

/// Service that initializes or resets the two canonical Syncro demo scenarios:
/// 1. **Friends Zone (Personal):** Mendy — outside work hours (Thu 19:00–22:00, Sat 12:00–18:00).
/// 2. **Mounjaro Clinical Study (Professional):** Patient 101 & Patient 102 — work hours only
///    (Mon/Wed 08:00–12:00, 45m + 15m buffers), 1-year 24-visit bi-weekly protocol roadmaps.
class DemoSeedService {
  static const String friendsZoneTypeId = 'type_friends_zone';
  static const String mounjaroStudyTypeId = 'type_mounjaro_study';

  static const String mendyEntityId = 'entity_mendy';
  static const String patient101EntityId = 'entity_patient_101';
  static const String patient102EntityId = 'entity_patient_102';

  static const String patient101EnrollmentId = 'enrollment_patient_101';
  static const String patient102EnrollmentId = 'enrollment_patient_102';

  final SchedulingRepository _repository;

  const DemoSeedService(this._repository);

  /// Seeds the database only if no EventTypes exist yet (idempotent first-boot initialization).
  Future<bool> seedIfEmpty({DateTime? referenceDate}) async {
    final existingTypes = await _repository.getAllEventTypes();
    if (existingTypes.isNotEmpty) {
      return false;
    }
    await resetAndSeed(referenceDate: referenceDate);
    return true;
  }

  /// Clears all existing scheduling data and populates a fresh, collision-free set
  /// of demo scenarios anchored at [referenceDate] (defaults to next Monday).
  Future<void> resetAndSeed({DateTime? referenceDate}) async {
    await _repository.clearAllData();

    final anchorMonday = _normalizeToMonday(
      referenceDate ?? DateTime(2026, 10, 19),
    );

    // 1. Seed Default Work Schedule (Mon-Fri, 08:00 - 18:00)
    const workSchedule = WorkSchedule(
      workDays: {
        DateTime.monday,
        DateTime.tuesday,
        DateTime.wednesday,
        DateTime.thursday,
        DateTime.friday,
      },
      startHour: 8,
      startMinute: 0,
      endHour: 18,
      endMinute: 0,
    );
    await _repository.saveWorkSchedule(workSchedule);

    // 2. Seed Event Types
    const friendsZoneType = EventType(
      id: friendsZoneTypeId,
      name: 'Friends Zone',
      colorHex: '#7C4DFF',
      workHoursConstraint: WorkHoursConstraint.outsideWorkHours,
      minDuration: Duration(minutes: 60),
      maxDuration: Duration(minutes: 90),
      bufferBefore: Duration.zero,
      bufferAfter: Duration.zero,
      schedulingMode: SchedulingMode.suggestTopRanked,
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

    const mounjaroStudyType = EventType(
      id: mounjaroStudyTypeId,
      name: 'Mounjaro Clinical Study',
      colorHex: '#00897B',
      workHoursConstraint: WorkHoursConstraint.workHoursOnly,
      minDuration: Duration(minutes: 45),
      maxDuration: Duration(minutes: 45),
      bufferBefore: Duration(minutes: 15),
      bufferAfter: Duration(minutes: 15),
      schedulingMode: SchedulingMode.instantAuto,
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

    await _repository.upsertEventType(friendsZoneType);
    await _repository.upsertEventType(mounjaroStudyType);

    // 3. Seed Entities (Mendy, Patient 101, Patient 102)
    const mendy = Entity(
      id: mendyEntityId,
      name: 'Mendy',
      phone: '+1 555-0199',
      email: 'mendy@example.com',
      defaultEventTypeId: friendsZoneTypeId,
    );

    const patient101 = Entity(
      id: patient101EntityId,
      name: 'Patient 101',
      phone: '+1 555-0101',
      email: 'patient101@clinical.example.org',
      defaultEventTypeId: mounjaroStudyTypeId,
    );

    const patient102 = Entity(
      id: patient102EntityId,
      name: 'Patient 102',
      phone: '+1 555-0102',
      email: 'patient102@clinical.example.org',
      defaultEventTypeId: mounjaroStudyTypeId,
      customAvailabilityOverrides: [
        DayTimeWindow(
          dayOfWeek: DateTime.wednesday,
          startHour: 10,
          endHour: 12,
        ),
      ],
    );

    await _repository.upsertEntity(mendy);
    await _repository.upsertEntity(patient101);
    await _repository.upsertEntity(patient102);

    // 4. Seed Protocol Enrollments (24 visits, 14-day cadence)
    final enrollment101 = ProtocolEnrollment(
      id: patient101EnrollmentId,
      entityId: patient101.id,
      eventTypeId: mounjaroStudyType.id,
      protocolName: 'Mounjaro Phase 3 — Cohort A',
      startDate: anchorMonday,
      totalVisits: 24,
      cadenceDays: 14,
      toleranceWindowDays: 3,
    );

    final enrollment102 = ProtocolEnrollment(
      id: patient102EnrollmentId,
      entityId: patient102.id,
      eventTypeId: mounjaroStudyType.id,
      protocolName: 'Mounjaro Phase 3 — Cohort B',
      startDate: anchorMonday,
      totalVisits: 24,
      cadenceDays: 14,
      toleranceWindowDays: 3,
    );

    await _repository.upsertProtocolEnrollment(enrollment101);
    await _repository.upsertProtocolEnrollment(enrollment102);

    // 5. Generate Collision-Free Appointments
    final List<Appointment> allSeededAppointments = [];
    final List<TimeRange> cumulativeBusySlots = [];

    // 5a. Patient 101: 24-visit sequence
    final visits101 = ProtocolCascadeService.generateInitialSequence(
      enrollment: enrollment101,
      eventType: mounjaroStudyType,
      workSchedule: workSchedule,
      entity: patient101,
      busySlots: cumulativeBusySlots,
    );
    allSeededAppointments.addAll(visits101);
    cumulativeBusySlots.addAll(visits101.map((a) => a.timeRange));

    // 5b. Patient 102: 24-visit sequence (respects Patient 101's slots + Wednesday 10:00-12:00 override)
    final visits102 = ProtocolCascadeService.generateInitialSequence(
      enrollment: enrollment102,
      eventType: mounjaroStudyType,
      workSchedule: workSchedule,
      entity: patient102,
      busySlots: cumulativeBusySlots,
    );
    allSeededAppointments.addAll(visits102);
    cumulativeBusySlots.addAll(visits102.map((a) => a.timeRange));

    // 5c. Mendy (Friends Zone): Find optimal Thursday evening slot in the first week
    final firstWeekRange = TimeRange(
      start: anchorMonday,
      end: anchorMonday.add(const Duration(days: 7)),
    );
    final mendyCandidateSlots = SlotFinder.findCandidateSlots(
      searchRange: firstWeekRange,
      eventType: friendsZoneType,
      workSchedule: workSchedule,
      entity: mendy,
      busySlots: cumulativeBusySlots,
      slotStep: const Duration(minutes: 30),
    );

    if (mendyCandidateSlots.isNotEmpty) {
      allSeededAppointments.add(
        Appointment(
          id: 'apt_mendy_hangout_1',
          entityId: mendy.id,
          eventTypeId: friendsZoneType.id,
          timeRange: mendyCandidateSlots.first,
          status: AppointmentStatus.suggested,
        ),
      );
    }

    await _repository.upsertAppointmentsBatch(allSeededAppointments);
  }

  static DateTime _normalizeToMonday(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final daysSinceMonday = (dayStart.weekday - DateTime.monday) % 7;
    if (daysSinceMonday == 0) return dayStart;
    return dayStart.subtract(Duration(days: daysSinceMonday));
  }
}
