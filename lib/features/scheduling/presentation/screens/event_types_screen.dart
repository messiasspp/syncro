import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/syncro_theme.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../domain/models/event_type.dart';
import '../providers/scheduling_providers.dart';
import '../widgets/confirmation_sheet.dart';

/// Tab 2: Glassmorphic Event Types & Rule Engine Management Screen.
class EventTypesScreen extends ConsumerWidget {
  const EventTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final eventTypesAsync = ref.watch(eventTypesStreamProvider);
    final eventTypes = eventTypesAsync.valueOrNull ?? const <EventType>[];
    final topPadding = MediaQuery.of(context).padding.top + kToolbarHeight + 14;

    return Stack(
      children: [
        ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, topPadding, 16, 155),
          children: [
            Text(
              strings.eventTypesHeader,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
            ),
            const SizedBox(height: 14),
            for (int i = 0; i < eventTypes.length; i++)
              StaggeredReveal(
                index: i,
                child: _EventTypeGlassCard(
                  eventType: eventTypes[i],
                  strings: strings,
                ),
              ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 112,
          child: AnimatedScaleTap(
            onTap: () => _showCreateEventTypeDialog(context, ref, strings),
            child: GlassContainer(
              borderRadius: 26,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              tintColor: Theme.of(context).colorScheme.primary,
              borderColor: Colors.white.withValues(alpha: 0.32),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    strings.newEventTypeButton,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showCreateEventTypeDialog(
    BuildContext context,
    WidgetRef ref,
    AppStrings strings,
  ) async {
    final nameCtrl = TextEditingController();
    final minDurCtrl = TextEditingController(text: '45');
    final maxDurCtrl = TextEditingController(text: '60');
    final bufBeforeCtrl = TextEditingController(text: '10');
    final bufAfterCtrl = TextEditingController(text: '10');
    var selectedConstraint = WorkHoursConstraint.outsideWorkHours;
    var selectedMode = SchedulingMode.suggestTopRanked;
    var selectedHex = '#6366F1';

    const colorOptions = [
      '#6366F1',
      '#14B8A6',
      '#EC4899',
      '#F59E0B',
      '#3B82F6',
    ];

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: Text(strings.newEventTypeButton),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: strings.isPt
                            ? 'Nome da Categoria'
                            : 'Category Name',
                        hintText: 'e.g. Tennis Club / Cardiology Study',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<WorkHoursConstraint>(
                      isExpanded: true,
                      initialValue: selectedConstraint,
                      decoration: InputDecoration(
                        labelText: strings.isPt
                            ? 'Regra de Expediente'
                            : 'Work Boundary Rule',
                      ),
                      items: [
                        DropdownMenuItem(
                          value: WorkHoursConstraint.workHoursOnly,
                          child: Text(strings.workHoursOnlyLabel),
                        ),
                        DropdownMenuItem(
                          value: WorkHoursConstraint.outsideWorkHours,
                          child: Text(strings.outsideWorkHoursLabel),
                        ),
                        DropdownMenuItem(
                          value: WorkHoursConstraint.bothFlexible,
                          child: Text(strings.bothFlexibleLabel),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setModalState(() => selectedConstraint = v);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<SchedulingMode>(
                      isExpanded: true,
                      initialValue: selectedMode,
                      decoration: InputDecoration(
                        labelText: strings.isPt
                            ? 'Modo de Alocação'
                            : 'Scheduling Mode',
                      ),
                      items: [
                        DropdownMenuItem(
                          value: SchedulingMode.instantAuto,
                          child: Text(strings.instantAutoLabel),
                        ),
                        DropdownMenuItem(
                          value: SchedulingMode.suggestTopRanked,
                          child: Text(strings.suggestTopRankedLabel),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setModalState(() => selectedMode = v);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minDurCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Min (min)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: maxDurCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Max (min)',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: bufBeforeCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Pre-Buffer (m)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: bufAfterCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Post-Buffer (m)',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      children: [
                        for (final hex in colorOptions)
                          GestureDetector(
                            onTap: () =>
                                setModalState(() => selectedHex = hex),
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: parseHexColor(hex),
                              child: selectedHex == hex
                                  ? const Icon(
                                      Icons.check,
                                      size: 16,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(strings.isPt ? 'Cancelar' : 'Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    final minMin = int.tryParse(minDurCtrl.text) ?? 45;
                    final maxMin = int.tryParse(maxDurCtrl.text) ?? minMin;
                    final preMin = int.tryParse(bufBeforeCtrl.text) ?? 0;
                    final postMin = int.tryParse(bufAfterCtrl.text) ?? 0;

                    final newEt = EventType(
                      id: 'et_${DateTime.now().millisecondsSinceEpoch}',
                      name: name,
                      colorHex: selectedHex,
                      workHoursConstraint: selectedConstraint,
                      minDuration: Duration(minutes: minMin),
                      maxDuration: Duration(
                        minutes: maxMin < minMin ? minMin : maxMin,
                      ),
                      bufferBefore: Duration(minutes: preMin),
                      bufferAfter: Duration(minutes: postMin),
                      schedulingMode: selectedMode,
                    );
                    await ref
                        .read(schedulingRepositoryProvider)
                        .upsertEventType(newEt);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  child: Text(strings.isPt ? 'Salvar' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _EventTypeGlassCard extends ConsumerWidget {
  final EventType eventType;
  final AppStrings strings;

  const _EventTypeGlassCard({
    required this.eventType,
    required this.strings,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = parseHexColor(eventType.colorHex);
    final constraintLabel = switch (eventType.workHoursConstraint) {
      WorkHoursConstraint.workHoursOnly => strings.workHoursOnlyLabel,
      WorkHoursConstraint.outsideWorkHours => strings.outsideWorkHoursLabel,
      WorkHoursConstraint.bothFlexible => strings.bothFlexibleLabel,
    };

    final modeLabel = eventType.schedulingMode == SchedulingMode.instantAuto
        ? strings.instantAutoLabel
        : strings.suggestTopRankedLabel;

    final minM = eventType.minDuration.inMinutes;
    final maxM = eventType.maxDuration.inMinutes;
    final durText = minM == maxM ? '$minM min' : '$minM–$maxM min';

    final preB = eventType.bufferBefore.inMinutes;
    final postB = eventType.bufferAfter.inMinutes;
    final bufText =
        (preB == 0 && postB == 0) ? 'None' : '${preB}m pre / ${postB}m post';

    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      borderColor: color.withValues(alpha: 0.42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.65),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  eventType.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.38)),
                ),
                child: Text(
                  constraintLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _GlassRulePill(
                icon: Icons.timer_outlined,
                label: strings.durationLabel,
                value: durText,
                accentColor: color,
              ),
              _GlassRulePill(
                icon: Icons.shield_outlined,
                label: strings.buffersLabel,
                value: bufText,
                accentColor: color,
              ),
              _GlassRulePill(
                icon: Icons.bolt_outlined,
                label: 'Mode',
                value: modeLabel,
                accentColor: color,
              ),
            ],
          ),
          if (eventType.allowedTimeWindows.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              strings.allowedWindowsLabel,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            for (final w in eventType.allowedTimeWindows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _DayWindowTimelineBar(
                  window: w,
                  strings: strings,
                  color: color,
                ),
              ),
          ],
          const Divider(height: 22),
          Row(
            children: [
              Icon(
                eventType.calendarMappingId != null
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_queue_rounded,
                size: 17,
                color: eventType.calendarMappingId != null
                    ? SyncroColors.clinicalEmerald
                    : Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  eventType.calendarMappingId != null
                      ? '${strings.subCalendarProvisioned} (${eventType.calendarMappingId})'
                      : strings.subCalendarPending,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.sync_rounded, size: 16),
                label: Text(
                  strings.isPt ? 'Criar/Vincular' : 'Link Calendar',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: () async {
                  await ref
                      .read(calendarSyncServiceProvider)
                      .ensureDedicatedCalendarForEventType(eventType);
                  ref.invalidate(externalCalendarsFutureProvider);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Visual 24-hour bar showing where a [DayTimeWindow] sits within the day.
class _DayWindowTimelineBar extends StatelessWidget {
  final DayTimeWindow window;
  final AppStrings strings;
  final Color color;

  const _DayWindowTimelineBar({
    required this.window,
    required this.strings,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final startFrac =
        ((window.startHour * 60 + window.startMinute) / 1440.0).clamp(0.0, 1.0);
    final endFrac =
        ((window.endHour * 60 + window.endMinute) / 1440.0).clamp(0.0, 1.0);
    final widthFrac = (endFrac - startFrac).clamp(0.05, 1.0);

    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            strings.weekdayName(window.dayOfWeek, short: true),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalW = constraints.maxWidth;
                return Stack(
                  children: [
                    Positioned(
                      left: totalW * startFrac,
                      width: totalW * widthFrac,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: LinearGradient(
                            colors: [
                              color,
                              color.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${window.startHour.toString().padLeft(2, '0')}:${window.startMinute.toString().padLeft(2, '0')}–'
          '${window.endHour.toString().padLeft(2, '0')}:${window.endMinute.toString().padLeft(2, '0')}',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _GlassRulePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;

  const _GlassRulePill({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accentColor),
          const SizedBox(width: 5),
          Text(
            '$label: ',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11.5,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}
