import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/syncro_theme.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/windowed_pager.dart';
import '../../domain/models/appointment.dart';
import '../../domain/models/entity.dart';
import '../../domain/models/event_type.dart';
import '../../domain/models/protocol_enrollment.dart';
import '../../domain/models/time_range.dart';
import '../../domain/models/work_schedule.dart';
import '../../domain/services/protocol_cascade_service.dart';
import '../../domain/services/slot_finder.dart';
import '../providers/scheduling_providers.dart';

/// Tab 4: Glassmorphic Interactive Smart Slot Finder & Protocol Cascade Diff Manager.
class SchedulerScreen extends ConsumerStatefulWidget {
  const SchedulerScreen({super.key});

  @override
  ConsumerState<SchedulerScreen> createState() => _SchedulerScreenState();
}

class _SchedulerScreenState extends ConsumerState<SchedulerScreen> {
  int _modeIndex = 0; // 0 = Slot Finder, 1 = Protocol Cascade
  String? _selectedEntityId;
  final Set<String> _extraEntityIds = {};
  int _recurrenceMode = 0; // 0 = Once, 1 = Weekly (4x), 2 = Biweekly (4x), 3 = Monthly (3x)
  String? _selectedEnrollmentId;
  int _selectedVisitIndex = 1;
  int _cascadeDayShiftOffset = 3; // Interactive drag shift in days (1..21)

  List<TimeRange> _candidateSlots = const [];
  bool _hasSearchedSlots = false;
  String? _lastCascadeSummary;
  Map<int, DateTime> _previousVisitStarts = const {};

  /// Windowed lazy loading for the candidate slot list and the protocol
  /// visit sequence (each: 8 per page, at most 24 mounted).
  final WindowedPager _slotsPager = WindowedPager(pageSize: 8, maxWindow: 24);
  final WindowedPager _visitsPager = WindowedPager(pageSize: 8, maxWindow: 24);

  @override
  void initState() {
    super.initState();
    void refresh() {
      if (mounted) setState(() {});
    }

    _slotsPager.attach(refresh);
    _visitsPager.attach(refresh);
  }

  @override
  void dispose() {
    _slotsPager.detach();
    _visitsPager.detach();
    super.dispose();
  }

  /// Builds `[Show earlier] + window items + [Load more footer]` for a list
  /// that lives inside the screen's outer scroll view.
  List<Widget> _windowedItems({
    required WindowedPager pager,
    required int total,
    required AppStrings strings,
    required Widget Function(int globalIndex) itemBuilder,
  }) {
    if (total == 0) return const [];
    final windowStart = pager.visibleStart(total);
    final windowEnd = pager.visibleEnd(total);
    return [
      if (pager.hasEarlier && windowStart > 0)
        PagerShowEarlierButton(
          label: strings.showEarlierLabel(windowStart),
          onTap: (ctx) => pager.loadEarlier(ctx, setState),
        ),
      for (var i = windowStart; i < windowEnd; i++)
        pager.measure(i, itemBuilder(i)),
      PagerFooter(
        hasMore: pager.hasMore(total),
        loadMoreLabel: strings.loadMoreLabel(pager.remaining(total)),
        rangeLabel: strings.windowRangeLabel(windowStart + 1, windowEnd, total),
        endLabel: strings.endOfListLabel,
        onLoadMore: (ctx) => pager.loadMore(ctx, total, setState),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final entitiesAsync = ref.watch(entitiesStreamProvider);
    final eventTypesAsync = ref.watch(eventTypesStreamProvider);
    final workScheduleAsync = ref.watch(workScheduleStreamProvider);
    final enrollmentsAsync = ref.watch(protocolEnrollmentsStreamProvider);
    final appointmentsAsync = ref.watch(appointmentsStreamProvider);

    final entities = entitiesAsync.valueOrNull ?? const <Entity>[];
    final eventTypes = eventTypesAsync.valueOrNull ?? const <EventType>[];
    final workSchedule = workScheduleAsync.valueOrNull ?? const WorkSchedule();
    final enrollments =
        enrollmentsAsync.valueOrNull ?? const <ProtocolEnrollment>[];
    final appointments = appointmentsAsync.valueOrNull ?? const <Appointment>[];

    final effectiveEntityId =
        _selectedEntityId ?? (entities.isNotEmpty ? entities.first.id : null);
    final effectiveEnrollmentId = _selectedEnrollmentId ??
        (enrollments.isNotEmpty ? enrollments.first.id : null);
    final topPadding = MediaQuery.of(context).padding.top + kToolbarHeight + 14;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 115),
      children: [
        // Glassmorphic Segmented Switcher
        GlassContainer(
          borderRadius: 24,
          padding: const EdgeInsets.all(5),
          child: Row(
            children: [
              Expanded(
                child: _ModeSegmentButton(
                  icon: Icons.search_rounded,
                  label: strings.slotFinderTab,
                  isSelected: _modeIndex == 0,
                  onTap: () => setState(() => _modeIndex = 0),
                ),
              ),
              Expanded(
                child: _ModeSegmentButton(
                  icon: Icons.account_tree_rounded,
                  label: strings.cascadeManagerTab,
                  isSelected: _modeIndex == 1,
                  onTap: () => setState(() => _modeIndex = 1),
                ),
              ),
            ],
          ),
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
    final selectedEntity =
        entities.where((e) => e.id == selectedEntityId).firstOrNull;
    final eventType = eventTypes
            .where((t) => t.id == selectedEntity?.defaultEventTypeId)
            .firstOrNull ??
        eventTypes.firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassContainer(
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (entities.isNotEmpty)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: selectedEntityId,
                  decoration: InputDecoration(
                    labelText:
                        strings.isPt ? 'Pessoa' : 'People',
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                  ),
                  items: entities
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.id,
                          child: Text(
                            e.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedEntityId = val;
                      if (val != null) _extraEntityIds.remove(val);
                      _candidateSlots = const [];
                      _hasSearchedSlots = false;
                    });
                  },
                ),
              if (entities.length > 1) ...[
                const SizedBox(height: 10),
                Text(
                  strings.isPt
                      ? 'Mais Pessoas (Reunião em Grupo)'
                      : 'Additional Peoples (Group Meeting)',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final e in entities)
                      if (e.id != selectedEntity?.id)
                        FilterChip(
                          label: Text(
                            e.name,
                            style: const TextStyle(fontSize: 12),
                          ),
                          visualDensity: VisualDensity.compact,
                          selected: _extraEntityIds.contains(e.id),
                          onSelected: (selected) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              if (selected) {
                                _extraEntityIds.add(e.id);
                              } else {
                                _extraEntityIds.remove(e.id);
                              }
                            });
                          },
                        ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              if (eventType != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.rule_folder_outlined),
                  title: Text(
                    '${strings.isPt ? "Grupo" : "Group"}: ${eventType.effectiveCode} • ${eventType.name}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${eventType.minDuration.inMinutes}m • '
                    'Buffer ${eventType.bufferBefore.inMinutes}m/${eventType.bufferAfter.inMinutes}m',
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                strings.isPt ? 'Recorrência' : 'Recurrence',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final (mode, label) in [
                    (0, strings.isPt ? 'Único (1x)' : 'Once (1x)'),
                    (1, strings.isPt ? 'Semanal (4x)' : 'Weekly (4x)'),
                    (2, strings.isPt ? 'Quinzenal (4x)' : 'Biweekly (4x)'),
                    (3, strings.isPt ? 'Mensal (3x)' : 'Monthly (3x)'),
                  ])
                    ChoiceChip(
                      label: Text(
                        label,
                        style: const TextStyle(fontSize: 12),
                      ),
                      visualDensity: VisualDensity.compact,
                      selected: _recurrenceMode == mode,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _recurrenceMode = mode);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(
                  strings.findOptimalSlotsButton,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: selectedEntity == null || eventType == null
                    ? null
                    : () async {
                        HapticFeedback.mediumImpact();
                        final now = DateTime.now();
                        final todayStart = DateTime(now.year, now.month, now.day);
                        final searchWindow = TimeRange(
                          start: todayStart,
                          end: todayStart.add(
                            const Duration(days: 14, hours: 23, minutes: 59),
                          ),
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
                          // Ranked results, revealed 8 at a time by the pager.
                          _candidateSlots = slots.take(40).toList();
                          _hasSearchedSlots = true;
                          _slotsPager.reset();
                        });
                      },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_hasSearchedSlots) ...[
          Text(
            strings.isPt
                ? 'Top ${_candidateSlots.length} Horários Disponíveis (Sem Colisões)'
                : 'Top ${_candidateSlots.length} Collision-Free Candidate Slots',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          ..._windowedItems(
            pager: _slotsPager,
            total: _candidateSlots.length,
            strings: strings,
            itemBuilder: (i) => StaggeredReveal(
              index: i % _slotsPager.pageSize,
              child: _CandidateSlotGlassCard(
                slot: _candidateSlots[i],
                rankIndex: i,
                strings: strings,
                onBook: selectedEntity == null || eventType == null
                    ? null
                    : () async {
                        HapticFeedback.mediumImpact();
                        final slot = _candidateSlots[i];
                        final selectedParticipants = <Entity>[
                          selectedEntity,
                          for (final e in entities)
                            if (e.id != selectedEntity.id &&
                                _extraEntityIds.contains(e.id))
                              e,
                        ];
                        final targetEntityId =
                            selectedParticipants.length == 1
                                ? selectedEntity.id
                                : selectedParticipants
                                    .map((e) => e.name)
                                    .join(', ');
                        final displayNames = selectedParticipants
                            .map((e) => e.name)
                            .join(', ');

                        final offsets = switch (_recurrenceMode) {
                          1 => const [0, 7, 14, 21],
                          2 => const [0, 14, 28, 42],
                          3 => const [0, 30, 60],
                          _ => const [0],
                        };
                        final baseMs = DateTime.now().millisecondsSinceEpoch;
                        for (int idx = 0; idx < offsets.length; idx++) {
                          final dayOffset = offsets[idx];
                          final shiftedRange = TimeRange(
                            start: slot.start.add(Duration(days: dayOffset)),
                            end: slot.end.add(Duration(days: dayOffset)),
                          );
                          final newApt = Appointment(
                            id: 'apt_${baseMs}_$idx',
                            entityId: targetEntityId,
                            eventTypeId: eventType.id,
                            timeRange: shiftedRange,
                            status: AppointmentStatus.confirmed,
                            visitIndex: offsets.length > 1 ? idx : null,
                          );
                          await ref
                              .read(schedulingRepositoryProvider)
                              .upsertAppointment(newApt);
                          await ref
                              .read(calendarSyncServiceProvider)
                              .pushAppointmentToCalendar(newApt);
                        }

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
                                    ? 'Agendado (${offsets.length}x) para $displayNames!'
                                    : 'Booked (${offsets.length}x) & synced for $displayNames!',
                              ),
                            ),
                          );
                        }
                      },
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
    final enrollment =
        enrollments.where((e) => e.id == selectedEnrollmentId).firstOrNull;
    final entity =
        entities.where((e) => e.id == enrollment?.entityId).firstOrNull;
    final eventType =
        eventTypes.where((t) => t.id == enrollment?.eventTypeId).firstOrNull;

    final protocolVisits = appointments
        .where((a) => a.protocolEnrollmentId == selectedEnrollmentId)
        .toList()
      ..sort((a, b) => (a.visitIndex ?? 0).compareTo(b.visitIndex ?? 0));

    final targetVisit = protocolVisits
        .where((v) => v.visitIndex == _selectedVisitIndex)
        .firstOrNull;

    // Live Dry-Run Cascade Calculation for Real-Time Diff Preview
    CascadeShiftResult? dryRunPreview;
    TimeRange? previewNewSlot;
    if (enrollment != null &&
        entity != null &&
        eventType != null &&
        targetVisit != null) {
      final searchStart = targetVisit.timeRange.start
          .add(Duration(days: _cascadeDayShiftOffset));
      final searchWindow = TimeRange(
        start: searchStart,
        end: searchStart.add(const Duration(days: 14)),
      );
      final candidateSlots = SlotFinder.findCandidateSlots(
        searchRange: searchWindow,
        eventType: eventType,
        workSchedule: workSchedule,
        entity: entity,
      );
      if (candidateSlots.isNotEmpty) {
        previewNewSlot = candidateSlots.first;
        dryRunPreview = ProtocolCascadeService.recalculateCascade(
          enrollment: enrollment,
          currentAppointments: protocolVisits,
          shiftedVisitIndex: _selectedVisitIndex,
          newSlot: previewNewSlot,
          eventType: eventType,
          workSchedule: workSchedule,
          entity: entity,
        );
      }
    }

    final previewVisitsByIndex = <int, Appointment>{
      if (dryRunPreview != null)
        for (final apt in dryRunPreview.updatedAppointments)
          if (apt.visitIndex != null) apt.visitIndex!: apt,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassContainer(
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
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
                    final ent =
                        entities.where((e) => e.id == enr.entityId).firstOrNull;
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
                      _visitsPager.reset();
                      _lastCascadeSummary = null;
                      _previousVisitStarts = const {};
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
                  prefixIcon: const Icon(Icons.event_repeat_rounded),
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
                        .primary
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.30),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${strings.isPt ? "Data Atual da Visita" : "Current Visit Date"} #${_selectedVisitIndex + 1}: '
                        '${strings.formatDateHeader(targetVisit.timeRange.start)} '
                        '(${strings.formatTimeRange(targetVisit.timeRange)})',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (previewNewSlot != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.trending_flat_rounded,
                              size: 16,
                              color: SyncroColors.clinicalEmerald,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${strings.isPt ? "Nova Data (Prévia)" : "Preview Shift"} (+$_cascadeDayShiftOffset d): '
                                '${strings.formatDateHeader(previewNewSlot.start)} '
                                '(${strings.formatTimeRange(previewNewSlot)})',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: SyncroColors.clinicalEmerald,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Interactive Drag-to-Reschedule Slider & Quick Shift Chips
                Row(
                  children: [
                    Icon(
                      Icons.linear_scale_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.isPt
                            ? 'Arraste para Adiar (+$_cascadeDayShiftOffset dias)'
                            : 'Drag to Shift Visit (+$_cascadeDayShiftOffset days)',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(Icons.calendar_month_rounded, size: 15),
                      label: Text(
                        strings.isPt ? 'Escolher Data' : 'Pick Date',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: targetVisit.timeRange.start
                              .add(Duration(days: _cascadeDayShiftOffset)),
                          firstDate: targetVisit.timeRange.start
                              .add(const Duration(days: 1)),
                          lastDate: targetVisit.timeRange.start
                              .add(const Duration(days: 60)),
                        );
                        if (picked != null) {
                          final diff = picked
                              .difference(DateTime(
                                targetVisit.timeRange.start.year,
                                targetVisit.timeRange.start.month,
                                targetVisit.timeRange.start.day,
                              ))
                              .inDays
                              .clamp(1, 30);
                          setState(() => _cascadeDayShiftOffset = diff);
                        }
                      },
                    ),
                  ],
                ),
                Slider(
                  value: _cascadeDayShiftOffset.toDouble().clamp(1.0, 21.0),
                  min: 1,
                  max: 21,
                  divisions: 20,
                  label: '+$_cascadeDayShiftOffset d',
                  onChanged: (v) {
                    final next = v.round();
                    if (next != _cascadeDayShiftOffset) {
                      HapticFeedback.selectionClick();
                      setState(() => _cascadeDayShiftOffset = next);
                    }
                  },
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final preset in const [2, 4, 7, 14])
                      ChoiceChip(
                        label: Text('+$preset d'),
                        selected: _cascadeDayShiftOffset == preset,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setState(() => _cascadeDayShiftOffset = preset);
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                icon: const Icon(Icons.fast_forward_rounded),
                label: Text(
                  strings.delayVisitAndCascadeButton,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: enrollment == null ||
                        entity == null ||
                        eventType == null ||
                        targetVisit == null ||
                        previewNewSlot == null
                    ? null
                    : () async {
                        HapticFeedback.heavyImpact();
                        // Snapshot current dates before cascade for Before -> After diff UI
                        final prevMap = <int, DateTime>{
                          for (final v in protocolVisits)
                            if (v.visitIndex != null)
                              v.visitIndex!: v.timeRange.start,
                        };

                        final result = await ref
                            .read(schedulingRepositoryProvider)
                            .rescheduleProtocolVisit(
                              protocolEnrollmentId: enrollment.id,
                              shiftedVisitIndex: _selectedVisitIndex,
                              newSlot: previewNewSlot!,
                            );

                        setState(() {
                          _previousVisitStarts = prevMap;
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
        if (_lastCascadeSummary != null) ...[
          const SizedBox(height: 14),
          GlassContainer(
            padding: const EdgeInsets.all(14),
            borderRadius: 16,
            tintColor: SyncroColors.clinicalEmerald,
            borderColor: SyncroColors.clinicalEmerald.withValues(alpha: 0.65),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _lastCascadeSummary!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          strings.isPt
              ? 'Sequência de Visitas do Protocolo (${protocolVisits.length} Visitas)'
              : 'Live Protocol Visit Sequence (${protocolVisits.length} Visits)',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        ..._windowedItems(
          pager: _visitsPager,
          total: protocolVisits.length,
          strings: strings,
          itemBuilder: (i) {
            final visit = protocolVisits[i];
            final vIdx = visit.visitIndex ?? -1;
            final committedPrev = _previousVisitStarts[vIdx];
            final previewApt = previewVisitsByIndex[vIdx];
            return _CascadeVisitDiffCard(
              visit: visit,
              previewVisit: previewApt,
              selectedVisitIndex: _selectedVisitIndex,
              previousStart: committedPrev,
              strings: strings,
            );
          },
        ),
      ],
    );
  }
}

class _ModeSegmentButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeSegmentButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    primary,
                    SyncroColors.amethystViolet,
                  ],
                )
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: isSelected ? Colors.white : null,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateSlotGlassCard extends StatelessWidget {
  final TimeRange slot;
  final int rankIndex;
  final AppStrings strings;
  final VoidCallback? onBook;

  const _CandidateSlotGlassCard({
    required this.slot,
    required this.rankIndex,
    required this.strings,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    final score = (99 - (rankIndex * 2)).clamp(85, 99);
    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: 16,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: SyncroColors.clinicalEmerald.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: SyncroColors.clinicalEmerald.withValues(alpha: 0.40),
              ),
            ),
            child: Column(
              children: [
                Text(
                  '$score%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: SyncroColors.clinicalEmerald,
                  ),
                ),
                const Text(
                  'MATCH',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    color: SyncroColors.clinicalEmerald,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.formatDateHeader(slot.start),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${strings.formatTimeRange(slot)} (${slot.duration.inMinutes} min)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: onBook,
            child: Text(
              strings.bookSlotButton,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _CascadeVisitDiffCard extends StatelessWidget {
  final Appointment visit;
  final Appointment? previewVisit;
  final int selectedVisitIndex;
  final DateTime? previousStart;
  final AppStrings strings;

  const _CascadeVisitDiffCard({
    required this.visit,
    this.previewVisit,
    required this.selectedVisitIndex,
    required this.previousStart,
    required this.strings,
  });

  @override
  Widget build(BuildContext context) {
    final vIdx = visit.visitIndex ?? 0;
    final isSelectedVisit = vIdx == selectedVisitIndex;
    final didShift =
        previousStart != null && previousStart != visit.timeRange.start;
    final willPreviewShift = !didShift &&
        previewVisit != null &&
        previewVisit!.timeRange.start != visit.timeRange.start;

    final int shiftDays = didShift
        ? visit.timeRange.start.difference(previousStart!).inDays
        : (willPreviewShift
            ? previewVisit!.timeRange.start
                .difference(visit.timeRange.start)
                .inDays
            : 0);

    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      borderRadius: 16,
      borderColor: didShift
          ? SyncroColors.clinicalEmerald.withValues(alpha: 0.50)
          : (willPreviewShift
              ? SyncroColors.amberSuggested.withValues(alpha: 0.45)
              : (isSelectedVisit
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.55)
                  : null)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: didShift
                ? SyncroColors.clinicalEmerald.withValues(alpha: 0.22)
                : (willPreviewShift
                    ? SyncroColors.amberSuggested.withValues(alpha: 0.20)
                    : Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.18)),
            child: Text(
              '${vIdx + 1}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: didShift
                    ? SyncroColors.clinicalEmerald
                    : (willPreviewShift
                        ? SyncroColors.amberSuggested
                        : Theme.of(context).colorScheme.primary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (didShift)
                  Text(
                    strings.formatDateHeader(previousStart!),
                    style: TextStyle(
                      fontSize: 11,
                      decoration: TextDecoration.lineThrough,
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withValues(alpha: 0.65),
                    ),
                  )
                else if (willPreviewShift)
                  Text(
                    strings.formatDateHeader(visit.timeRange.start),
                    style: TextStyle(
                      fontSize: 11,
                      decoration: TextDecoration.lineThrough,
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withValues(alpha: 0.65),
                    ),
                  ),
                Text(
                  strings.formatDateHeader(
                    willPreviewShift
                        ? previewVisit!.timeRange.start
                        : visit.timeRange.start,
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: didShift
                        ? SyncroColors.clinicalEmerald
                        : (willPreviewShift
                            ? SyncroColors.amberSuggested
                            : null),
                  ),
                ),
                Text(
                  strings.formatTimeRange(
                    willPreviewShift ? previewVisit!.timeRange : visit.timeRange,
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (didShift || willPreviewShift)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (didShift
                        ? SyncroColors.clinicalEmerald
                        : SyncroColors.amberSuggested)
                    .withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                didShift
                    ? 'CASCADED ${shiftDays >= 0 ? "+$shiftDays" : "$shiftDays"}d'
                    : 'PREVIEW ${shiftDays >= 0 ? "+$shiftDays" : "$shiftDays"}d',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  color: didShift
                      ? SyncroColors.clinicalEmerald
                      : SyncroColors.amberSuggested,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
