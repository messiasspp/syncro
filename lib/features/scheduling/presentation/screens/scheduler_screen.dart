import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../domain/models/appointment.dart';
import '../../domain/models/entity.dart';
import '../../domain/models/event_type.dart';
import '../../domain/models/protocol_enrollment.dart';
import '../../domain/models/time_range.dart';
import '../../domain/models/work_schedule.dart';
import '../../domain/services/slot_finder.dart';
import '../providers/scheduling_providers.dart';

/// Tab 4: Interactive Smart Slot Finder & Protocol Cascade Manager.
class SchedulerScreen extends ConsumerStatefulWidget {
  const SchedulerScreen({super.key});

  @override
  ConsumerState<SchedulerScreen> createState() => _SchedulerScreenState();
}

class _SchedulerScreenState extends ConsumerState<SchedulerScreen> {
  int _modeIndex = 0; // 0 = Slot Finder, 1 = Protocol Cascade
  String? _selectedEntityId;
  String? _selectedEnrollmentId;
  int _selectedVisitIndex = 1;

  List<TimeRange> _candidateSlots = const [];
  bool _hasSearchedSlots = false;
  String? _lastCascadeSummary;

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final entities =
        ref.watch(entitiesStreamProvider).valueOrNull ?? const <Entity>[];
    final eventTypes =
        ref.watch(eventTypesStreamProvider).valueOrNull ?? const <EventType>[];
    final enrollments = ref
            .watch(protocolEnrollmentsStreamProvider)
            .valueOrNull ??
        const <ProtocolEnrollment>[];
    final appointments = ref.watch(appointmentsStreamProvider).valueOrNull ??
        const <Appointment>[];
    final workSchedule =
        ref.watch(workScheduleStreamProvider).valueOrNull ??
            const WorkSchedule();

    final effectiveEntityId =
        _selectedEntityId ?? (entities.isNotEmpty ? entities.first.id : null);
    final effectiveEnrollmentId = _selectedEnrollmentId ??
        (enrollments.isNotEmpty ? enrollments.first.id : null);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        SegmentedButton<int>(
          segments: [
            ButtonSegment(
              value: 0,
              icon: const Icon(Icons.search_rounded),
              label: Text(strings.slotFinderTab),
            ),
            ButtonSegment(
              value: 1,
              icon: const Icon(Icons.account_tree_outlined),
              label: Text(strings.cascadeManagerTab),
            ),
          ],
          selected: {_modeIndex},
          onSelectionChanged: (selection) {
            setState(() => _modeIndex = selection.first);
          },
        ),
        const SizedBox(height: 16),
        if (_modeIndex == 0)
          _buildSlotFinderSection(
            context: context,
            strings: strings,
            entities: entities,
            eventTypes: eventTypes,
            workSchedule: workSchedule,
            selectedEntityId: effectiveEntityId,
          )
        else
          _buildCascadeSection(
            context: context,
            strings: strings,
            enrollments: enrollments,
            entities: entities,
            eventTypes: eventTypes,
            appointments: appointments,
            workSchedule: workSchedule,
            selectedEnrollmentId: effectiveEnrollmentId,
          ),
      ],
    );
  }

  Widget _buildSlotFinderSection({
    required BuildContext context,
    required AppStrings strings,
    required List<Entity> entities,
    required List<EventType> eventTypes,
    required WorkSchedule workSchedule,
    required String? selectedEntityId,
  }) {
    final selectedEntity = entities
        .where((e) => e.id == selectedEntityId)
        .firstOrNull;
    final eventType = eventTypes
            .where((t) => t.id == selectedEntity?.defaultEventTypeId)
            .firstOrNull ??
        eventTypes.firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (entities.isNotEmpty)
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: selectedEntityId,
                    decoration: InputDecoration(
                      labelText: strings.isPt ? 'Participante' : 'Participant (Entity)',
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    items: entities
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.id,
                            child: Text(e.name),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedEntityId = val;
                        _candidateSlots = const [];
                        _hasSearchedSlots = false;
                      });
                    },
                  ),
                const SizedBox(height: 12),
                if (eventType != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.rule_folder_outlined),
                    title: Text(
                      '${strings.isPt ? "Categoria" : "Category"}: ${eventType.name}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${eventType.minDuration.inMinutes}m • '
                      'Buffer ${eventType.bufferBefore.inMinutes}m/${eventType.bufferAfter.inMinutes}m',
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(strings.findOptimalSlotsButton),
                  onPressed: selectedEntity == null || eventType == null
                      ? null
                      : () async {
                          final searchWindow = TimeRange(
                            start: DateTime(2026, 10, 19),
                            end: DateTime(2026, 11, 2, 23, 59),
                          );
                          final busy = await ref
                              .read(calendarSyncServiceProvider)
                              .fetchMergedBusySlots(searchWindow);

                          final slots = SlotFinder.findCandidateSlots(
                            searchRange: searchWindow,
                            eventType: eventType,
                            workSchedule: workSchedule,
                            entity: selectedEntity,
                            busySlots: busy,
                            slotStep: const Duration(minutes: 30),
                          );

                          setState(() {
                            _candidateSlots = slots.take(8).toList();
                            _hasSearchedSlots = true;
                          });
                        },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_hasSearchedSlots) ...[
          Text(
            strings.isPt
                ? 'Top ${_candidateSlots.length} Horários Disponíveis (Sem Colisões)'
                : 'Top ${_candidateSlots.length} Collision-Free Candidate Slots',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          for (final slot in _candidateSlots)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: ListTile(
                leading: Icon(
                  Icons.access_time_filled,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  strings.formatDateHeader(slot.start),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${strings.formatTimeRange(slot)} (${slot.duration.inMinutes} min)',
                ),
                trailing: FilledButton.tonal(
                  onPressed: selectedEntity == null || eventType == null
                      ? null
                      : () async {
                          final newApt = Appointment(
                            id: 'apt_${DateTime.now().millisecondsSinceEpoch}',
                            entityId: selectedEntity.id,
                            eventTypeId: eventType.id,
                            timeRange: slot,
                            status: AppointmentStatus.confirmed,
                          );
                          await ref
                              .read(schedulingRepositoryProvider)
                              .upsertAppointment(newApt);
                          await ref
                              .read(calendarSyncServiceProvider)
                              .pushAppointmentToCalendar(newApt);

                          setState(() {
                            _candidateSlots = _candidateSlots
                                .where((s) => s != slot)
                                .toList();
                          });

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  strings.isPt
                                      ? 'Agendado e sincronizado para ${selectedEntity.name}!'
                                      : 'Booked & synced for ${selectedEntity.name}!',
                                ),
                              ),
                            );
                          }
                        },
                  child: Text(strings.bookSlotButton),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildCascadeSection({
    required BuildContext context,
    required AppStrings strings,
    required List<ProtocolEnrollment> enrollments,
    required List<Entity> entities,
    required List<EventType> eventTypes,
    required List<Appointment> appointments,
    required WorkSchedule workSchedule,
    required String? selectedEnrollmentId,
  }) {
    final enrollment = enrollments
        .where((e) => e.id == selectedEnrollmentId)
        .firstOrNull;
    final entity = entities
        .where((e) => e.id == enrollment?.entityId)
        .firstOrNull;
    final eventType = eventTypes
        .where((t) => t.id == enrollment?.eventTypeId)
        .firstOrNull;

    final protocolVisits = appointments
        .where((a) => a.protocolEnrollmentId == selectedEnrollmentId)
        .toList()
      ..sort((a, b) => (a.visitIndex ?? 0).compareTo(b.visitIndex ?? 0));

    final targetVisit = protocolVisits
        .where((v) => v.visitIndex == _selectedVisitIndex)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (enrollments.isNotEmpty)
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: selectedEnrollmentId,
                    decoration: InputDecoration(
                      labelText: strings.isPt
                          ? 'Protocolo Clínico'
                          : 'Clinical Protocol Enrollment',
                      prefixIcon: const Icon(Icons.science_outlined),
                    ),
                    items: enrollments.map((enr) {
                      final ent = entities
                          .where((e) => e.id == enr.entityId)
                          .firstOrNull;
                      return DropdownMenuItem(
                        value: enr.id,
                        child: Text(
                          '${ent?.name ?? enr.entityId} • ${enr.protocolName}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedEnrollmentId = val;
                        _lastCascadeSummary = null;
                      });
                    },
                  ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _selectedVisitIndex,
                  decoration: InputDecoration(
                    labelText: strings.isPt
                        ? 'Selecionar Visita para Remarcar'
                        : 'Select Visit to Reschedule',
                    prefixIcon: const Icon(Icons.event_repeat),
                  ),
                  items: [
                    for (int i = 0; i < (enrollment?.totalVisits ?? 6); i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text('Visit #${i + 1}'),
                      ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedVisitIndex = val);
                    }
                  },
                ),
                if (targetVisit != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${strings.isPt ? "Data Atual da Visita" : "Current Visit Date"} #${_selectedVisitIndex + 1}: '
                      '${strings.formatDateHeader(targetVisit.timeRange.start)} '
                      '(${strings.formatTimeRange(targetVisit.timeRange)})',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  icon: const Icon(Icons.fast_forward_rounded),
                  label: Text(strings.delayVisitAndCascadeButton),
                  onPressed: enrollment == null ||
                          entity == null ||
                          eventType == null ||
                          targetVisit == null
                      ? null
                      : () async {
                          final searchStart = targetVisit.timeRange.start
                              .add(const Duration(days: 2));
                          final searchWindow = TimeRange(
                            start: searchStart,
                            end: searchStart.add(const Duration(days: 10)),
                          );

                          final candidateSlots = SlotFinder.findCandidateSlots(
                            searchRange: searchWindow,
                            eventType: eventType,
                            workSchedule: workSchedule,
                            entity: entity,
                          );

                          if (candidateSlots.isEmpty) return;

                          final newSlot = candidateSlots.first;
                          final result = await ref
                              .read(schedulingRepositoryProvider)
                              .rescheduleProtocolVisit(
                                protocolEnrollmentId: enrollment.id,
                                shiftedVisitIndex: _selectedVisitIndex,
                                newSlot: newSlot,
                              );

                          setState(() {
                            _lastCascadeSummary =
                                '${strings.cascadeSuccessBanner}\n'
                                '• Shifted visits: ${result.shiftedVisitIndices.length} '
                                '(Visit #${_selectedVisitIndex + 1} → Visit #${enrollment.totalVisits})';
                          });
                        },
                ),
              ],
            ),
          ),
        ),
        if (_lastCascadeSummary != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal.shade600),
            ),
            child: Text(
              _lastCascadeSummary!,
              style: TextStyle(
                color: Colors.teal.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          strings.isPt
              ? 'Sequência Atual do Protocolo (${protocolVisits.length} Visitas)'
              : 'Live Protocol Visit Sequence (${protocolVisits.length} Visits)',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        for (final apt in protocolVisits.take(8))
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 6),
            color: apt.visitIndex == _selectedVisitIndex
                ? Theme.of(context).colorScheme.primaryContainer.withValues(
                      alpha: 0.45,
                    )
                : null,
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                child: Text(
                  '${(apt.visitIndex ?? 0) + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                strings.formatDateHeader(apt.timeRange.start),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(strings.formatTimeRange(apt.timeRange)),
            ),
          ),
      ],
    );
  }
}
