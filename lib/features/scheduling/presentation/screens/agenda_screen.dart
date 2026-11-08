import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../domain/models/appointment.dart';
import '../../domain/models/entity.dart';
import '../../domain/models/event_type.dart';
import '../providers/scheduling_providers.dart';
import '../widgets/confirmation_sheet.dart';

/// Tab 1: Agenda & Timeline View displaying scheduled and suggested appointments
/// across all dedicated EventType calendars.
class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  String? _selectedEventTypeId;

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final eventTypesAsync = ref.watch(eventTypesStreamProvider);
    final entitiesAsync = ref.watch(entitiesStreamProvider);
    final appointmentsAsync = ref.watch(appointmentsStreamProvider);

    final eventTypes = eventTypesAsync.valueOrNull ?? const <EventType>[];
    final entities = entitiesAsync.valueOrNull ?? const <Entity>[];
    final allAppointments =
        appointmentsAsync.valueOrNull ?? const <Appointment>[];

    final Map<String, EventType> typesById = {
      for (final t in eventTypes) t.id: t,
    };
    final Map<String, Entity> entitiesById = {
      for (final e in entities) e.id: e,
    };

    final filteredAppointments = _selectedEventTypeId == null
        ? allAppointments
        : allAppointments
            .where((a) => a.eventTypeId == _selectedEventTypeId)
            .toList();

    final confirmedCount = filteredAppointments
        .where((a) => a.status == AppointmentStatus.confirmed)
        .length;
    final suggestedCount = filteredAppointments
        .where((a) => a.status == AppointmentStatus.suggested)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. KPI Summary Strip
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              _StatBadge(
                label: strings.totalAppointmentsLabel,
                value: '${filteredAppointments.length}',
                color: Theme.of(context).colorScheme.primary,
                icon: Icons.event_note,
              ),
              const SizedBox(width: 8),
              _StatBadge(
                label: strings.confirmedLabel,
                value: '$confirmedCount',
                color: Colors.teal.shade700,
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(width: 8),
              _StatBadge(
                label: strings.suggestedLabel,
                value: '$suggestedCount',
                color: Colors.amber.shade800,
                icon: Icons.auto_awesome_outlined,
              ),
            ],
          ),
        ),

        // 2. Category Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              FilterChip(
                label: Text(strings.allFilter),
                selected: _selectedEventTypeId == null,
                onSelected: (_) => setState(() => _selectedEventTypeId = null),
              ),
              const SizedBox(width: 8),
              for (final et in eventTypes) ...[
                FilterChip(
                  avatar: CircleAvatar(
                    backgroundColor: parseHexColor(et.colorHex),
                    radius: 6,
                  ),
                  label: Text(et.name),
                  selected: _selectedEventTypeId == et.id,
                  onSelected: (_) => setState(
                    () => _selectedEventTypeId =
                        _selectedEventTypeId == et.id ? null : et.id,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const Divider(height: 12),

        // 3. Timeline List
        Expanded(
          child: filteredAppointments.isEmpty
              ? Center(
                  child: Text(
                    strings.noAppointmentsFound,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: filteredAppointments.length,
                  itemBuilder: (context, index) {
                    final apt = filteredAppointments[index];
                    final eventType = typesById[apt.eventTypeId];
                    final entity = entitiesById[apt.entityId];
                    final color = parseHexColor(
                      eventType?.colorHex ?? '#2196F3',
                    );

                    final prevApt =
                        index > 0 ? filteredAppointments[index - 1] : null;
                    final showDateHeader = prevApt == null ||
                        prevApt.timeRange.start.year !=
                            apt.timeRange.start.year ||
                        prevApt.timeRange.start.month !=
                            apt.timeRange.start.month ||
                        prevApt.timeRange.start.day != apt.timeRange.start.day;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showDateHeader)
                          Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 6),
                            child: Text(
                              strings.formatDateHeader(apt.timeRange.start),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                            ),
                          ),
                        Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: color.withValues(alpha: 0.35),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => ConfirmationSheet.show(
                              context,
                              appointment: apt,
                              entity: entity,
                              eventType: eventType,
                              strings: strings,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 5,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                entity?.name ?? apt.entityId,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                              ),
                                            ),
                                            if (apt.visitIndex != null)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: color.withValues(
                                                    alpha: 0.14,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: Text(
                                                  'Visit #${apt.visitIndex! + 1}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: color,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${eventType?.name ?? apt.eventTypeId} • ${strings.formatTimeRange(apt.timeRange)} (${apt.timeRange.duration.inMinutes}m)',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            _StatusChip(
                                              status: apt.status,
                                              strings: strings,
                                            ),
                                            if (apt.externalCalendarEventId !=
                                                null)
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.cloud_done_outlined,
                                                    size: 14,
                                                    color: Colors.teal.shade700,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    strings.syncedBadge,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color:
                                                          Colors.teal.shade700,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (apt.status ==
                                          AppointmentStatus.suggested)
                                        IconButton.filledTonal(
                                          tooltip: strings.confirmAction,
                                          icon: const Icon(
                                            Icons.check_rounded,
                                            size: 18,
                                          ),
                                          onPressed: () async {
                                            final updated = apt.copyWith(
                                              status:
                                                  AppointmentStatus.confirmed,
                                            );
                                            await ref
                                                .read(
                                                  schedulingRepositoryProvider,
                                                )
                                                .upsertAppointment(updated);
                                            await ref
                                                .read(
                                                  calendarSyncServiceProvider,
                                                )
                                                .pushAppointmentToCalendar(
                                                  updated,
                                                );
                                          },
                                        ),
                                      IconButton(
                                        tooltip: strings.shareAction,
                                        icon: const Icon(
                                          Icons.share_outlined,
                                          size: 18,
                                        ),
                                        onPressed: () => ConfirmationSheet.show(
                                          context,
                                          appointment: apt,
                                          entity: entity,
                                          eventType: eventType,
                                          strings: strings,
                                        ),
                                      ),
                                    ],
                                  ),
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
      ],
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatBadge({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final AppointmentStatus status;
  final AppStrings strings;

  const _StatusChip({
    required this.status,
    required this.strings,
  });

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (status) {
      AppointmentStatus.confirmed => (
          strings.confirmedLabel,
          Colors.teal.shade700,
        ),
      AppointmentStatus.suggested => (
          strings.suggestedLabel,
          Colors.amber.shade800,
        ),
      AppointmentStatus.completed => (
          strings.completedLabel,
          Colors.blueGrey,
        ),
      AppointmentStatus.cancelled => (
          strings.cancelledLabel,
          Colors.red.shade700,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
