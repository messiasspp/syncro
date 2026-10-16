import '../models/appointment.dart';
import '../models/entity.dart';
import '../models/event_type.dart';
import '../models/protocol_enrollment.dart';
import '../models/time_range.dart';
import '../models/work_schedule.dart';
import 'slot_finder.dart';

/// Result summary of a protocol cascading rescheduling operation.
class CascadeShiftResult {
  final List<Appointment> updatedAppointments;
  final List<int> shiftedVisitIndices;
  final List<int> unresolvableVisitIndices;

  const CascadeShiftResult({
    required this.updatedAppointments,
    required this.shiftedVisitIndices,
    required this.unresolvableVisitIndices,
  });
}

/// Service that handles structured multi-visit sequences (e.g., 24 clinical research visits).
///
/// When an appointment shifts, this engine automatically cascades and recalculates
/// downstream visits to preserve the required protocol cadence (e.g. 14 days between visits).
class ProtocolCascadeService {
  /// Generates initial appointment sequence for an enrolled participant across all [totalVisits].
  static List<Appointment> generateInitialSequence({
    required ProtocolEnrollment enrollment,
    required EventType eventType,
    required WorkSchedule workSchedule,
    required Entity entity,
    List<TimeRange> busySlots = const [],
  }) {
    final List<Appointment> sequence = [];
    final List<TimeRange> cumulativeBusy = List.of(busySlots);

    for (int i = 0; i < enrollment.totalVisits; i++) {
      final nominalTarget = enrollment.nominalDateForVisit(i);
      final searchWindow = enrollment.targetWindowForVisit(i);

      final candidateSlots = SlotFinder.findCandidateSlots(
        searchRange: searchWindow,
        eventType: eventType,
        workSchedule: workSchedule,
        entity: entity,
        busySlots: cumulativeBusy,
        preferredTargetTime: nominalTarget,
      );

      if (candidateSlots.isNotEmpty) {
        final chosenSlot = candidateSlots.first;
        final appointment = Appointment(
          id: '${enrollment.id}_visit_$i',
          entityId: entity.id,
          eventTypeId: eventType.id,
          timeRange: chosenSlot,
          status: i == 0 ? AppointmentStatus.confirmed : AppointmentStatus.suggested,
          visitIndex: i,
          protocolEnrollmentId: enrollment.id,
        );
        sequence.add(appointment);
        cumulativeBusy.add(chosenSlot);
      }
    }

    return sequence;
  }

  /// Recalculates and cascades downstream visits when visit [shiftedVisitIndex] is rescheduled to [newSlot].
  static CascadeShiftResult recalculateCascade({
    required ProtocolEnrollment enrollment,
    required List<Appointment> currentAppointments,
    required int shiftedVisitIndex,
    required TimeRange newSlot,
    required EventType eventType,
    required WorkSchedule workSchedule,
    required Entity entity,
    List<TimeRange> externalBusySlots = const [],
  }) {
    final Map<int, Appointment> appointmentsByVisit = {
      for (final apt in currentAppointments)
        if (apt.visitIndex != null) apt.visitIndex!: apt
    };

    final List<int> shiftedIndices = [];
    final List<int> unresolvableIndices = [];

    // 1. Update the target visit
    final updatedTargetApt = (appointmentsByVisit[shiftedVisitIndex] ??
            Appointment(
              id: '${enrollment.id}_visit_$shiftedVisitIndex',
              entityId: entity.id,
              eventTypeId: eventType.id,
              timeRange: newSlot,
              visitIndex: shiftedVisitIndex,
              protocolEnrollmentId: enrollment.id,
            ))
        .copyWith(timeRange: newSlot, status: AppointmentStatus.confirmed);

    appointmentsByVisit[shiftedVisitIndex] = updatedTargetApt;
    shiftedIndices.add(shiftedVisitIndex);

    // Cumulative busy tracker to prevent cascading visits from colliding with each other or external events
    final List<TimeRange> cumulativeBusy = List.of(externalBusySlots);
    for (final entry in appointmentsByVisit.entries) {
      if (entry.key < shiftedVisitIndex) {
        cumulativeBusy.add(entry.value.timeRange);
      }
    }
    cumulativeBusy.add(newSlot);

    // 2. Cascade forward for visits (shiftedVisitIndex + 1) to (totalVisits - 1)
    DateTime anchorDate = newSlot.start;

    for (int j = shiftedVisitIndex + 1; j < enrollment.totalVisits; j++) {
      // The new nominal date for visit j is anchored from the preceding visit's actual date
      final nominalDate = anchorDate.add(Duration(days: enrollment.cadenceDays));
      final searchWindow = TimeRange(
        start: DateTime(
          nominalDate.year,
          nominalDate.month,
          nominalDate.day - enrollment.toleranceWindowDays,
          0,
          0,
        ),
        end: DateTime(
          nominalDate.year,
          nominalDate.month,
          nominalDate.day + enrollment.toleranceWindowDays,
          23,
          59,
          59,
        ),
      );

      final candidateSlots = SlotFinder.findCandidateSlots(
        searchRange: searchWindow,
        eventType: eventType,
        workSchedule: workSchedule,
        entity: entity,
        busySlots: cumulativeBusy,
        preferredTargetTime: nominalDate,
      );

      if (candidateSlots.isNotEmpty) {
        final optimalSlot = candidateSlots.first;
        final existingApt = appointmentsByVisit[j];

        final updatedApt = (existingApt ??
                Appointment(
                  id: '${enrollment.id}_visit_$j',
                  entityId: entity.id,
                  eventTypeId: eventType.id,
                  timeRange: optimalSlot,
                  visitIndex: j,
                  protocolEnrollmentId: enrollment.id,
                ))
            .copyWith(timeRange: optimalSlot);

        appointmentsByVisit[j] = updatedApt;
        shiftedIndices.add(j);
        cumulativeBusy.add(optimalSlot);
        anchorDate = optimalSlot.start;
      } else {
        unresolvableIndices.add(j);
      }
    }

    final sortedList = appointmentsByVisit.values.toList()
      ..sort((a, b) => (a.visitIndex ?? 0).compareTo(b.visitIndex ?? 0));

    return CascadeShiftResult(
      updatedAppointments: sortedList,
      shiftedVisitIndices: shiftedIndices,
      unresolvableVisitIndices: unresolvableIndices,
    );
  }
}
