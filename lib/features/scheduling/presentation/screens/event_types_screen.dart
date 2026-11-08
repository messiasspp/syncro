import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../domain/models/event_type.dart';
import '../providers/scheduling_providers.dart';
import '../widgets/confirmation_sheet.dart';

/// Tab 2: Event Types & Rule Engine Management Screen.
class EventTypesScreen extends ConsumerWidget {
  const EventTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final eventTypesAsync = ref.watch(eventTypesStreamProvider);
    final eventTypes = eventTypesAsync.valueOrNull ?? const <EventType>[];

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: [
          Text(
            strings.eventTypesHeader,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          for (final et in eventTypes)
            _EventTypeCard(
              eventType: et,
              strings: strings,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEventTypeDialog(context, ref, strings),
        icon: const Icon(Icons.add),
        label: Text(strings.newEventTypeButton),
      ),
    );
  }

  Future<void> _showAddEventTypeDialog(
    BuildContext context,
    WidgetRef ref,
    AppStrings strings,
  ) async {
    final nameController = TextEditingController();
    WorkHoursConstraint constraint = WorkHoursConstraint.bothFlexible;
    int durationMins = 60;
    int bufferMins = 10;
    String selectedColor = '#E91E63';

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(strings.newEventTypeButton),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: strings.isPt ? 'Nome da Categoria' : 'Category Name',
                        hintText: strings.isPt ? 'Ex: Mentoria / Pilates' : 'e.g. Fitness / Coaching',
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<WorkHoursConstraint>(
                      initialValue: constraint,
                      decoration: InputDecoration(
                        labelText: strings.isPt ? 'Regra de Horário' : 'Work Hours Boundary',
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
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => constraint = val);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: durationMins,
                            decoration: InputDecoration(
                              labelText: '${strings.durationLabel} (min)',
                            ),
                            items: const [30, 45, 60, 90, 120]
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text('${m}m'),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => durationMins = v);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: bufferMins,
                            decoration: InputDecoration(
                              labelText: '${strings.buffersLabel} (min)',
                            ),
                            items: const [0, 5, 10, 15, 30]
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text('${m}m'),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => bufferMins = v);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final hex in const [
                          '#E91E63',
                          '#7C4DFF',
                          '#00897B',
                          '#FF6D00',
                          '#1E88E5',
                        ])
                          GestureDetector(
                            onTap: () =>
                                setDialogState(() => selectedColor = hex),
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: parseHexColor(hex),
                              child: selectedColor == hex
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
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    final newType = EventType(
                      id: 'type_${DateTime.now().millisecondsSinceEpoch}',
                      name: name,
                      colorHex: selectedColor,
                      workHoursConstraint: constraint,
                      minDuration: Duration(minutes: durationMins),
                      maxDuration: Duration(minutes: durationMins),
                      bufferBefore: Duration(minutes: bufferMins),
                      bufferAfter: Duration(minutes: bufferMins),
                    );
                    await ref
                        .read(schedulingRepositoryProvider)
                        .upsertEventType(newType);
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

class _EventTypeCard extends ConsumerWidget {
  final EventType eventType;
  final AppStrings strings;

  const _EventTypeCard({
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

    final modeLabel = switch (eventType.schedulingMode) {
      SchedulingMode.instantAuto => strings.instantAutoLabel,
      SchedulingMode.suggestTopRanked => strings.suggestTopRankedLabel,
    };

    final durText = eventType.minDuration == eventType.maxDuration
        ? '${eventType.minDuration.inMinutes} min'
        : '${eventType.minDuration.inMinutes}–${eventType.maxDuration.inMinutes} min';

    final bufText =
        '${eventType.bufferBefore.inMinutes}m pre / ${eventType.bufferAfter.inMinutes}m post';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.45), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color,
                  radius: 10,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    eventType.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Chip(
                  label: Text(
                    constraintLabel,
                    style: const TextStyle(fontSize: 11),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _RuleMetric(
                  icon: Icons.timer_outlined,
                  label: strings.durationLabel,
                  value: durText,
                ),
                _RuleMetric(
                  icon: Icons.shield_outlined,
                  label: strings.buffersLabel,
                  value: bufText,
                ),
                _RuleMetric(
                  icon: Icons.bolt_outlined,
                  label: 'Mode',
                  value: modeLabel,
                ),
              ],
            ),
            if (eventType.allowedTimeWindows.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                strings.allowedWindowsLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final w in eventType.allowedTimeWindows)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${strings.weekdayName(w.dayOfWeek, short: true)} '
                        '${w.startHour.toString().padLeft(2, '0')}:${w.startMinute.toString().padLeft(2, '0')}–'
                        '${w.endHour.toString().padLeft(2, '0')}:${w.endMinute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const Divider(height: 20),
            Row(
              children: [
                Icon(
                  eventType.calendarMappingId != null
                      ? Icons.event_available
                      : Icons.event_busy_outlined,
                  size: 16,
                  color: eventType.calendarMappingId != null
                      ? Colors.teal.shade700
                      : Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    eventType.calendarMappingId != null
                        ? '${strings.subCalendarProvisioned} (${eventType.calendarMappingId})'
                        : strings.subCalendarPending,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.sync, size: 16),
                  label: Text(strings.isPt ? 'Criar/Vincular' : 'Link Calendar'),
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
      ),
    );
  }
}

class _RuleMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _RuleMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
