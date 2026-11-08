import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../domain/models/appointment.dart';
import '../../domain/models/entity.dart';
import '../../domain/models/event_type.dart';
import '../../domain/models/protocol_enrollment.dart';
import '../providers/scheduling_providers.dart';
import '../widgets/confirmation_sheet.dart';

/// Tab 3: Directory of Participants (Friends & Clinical Patients) with Protocol Roadmaps.
class EntitiesScreen extends ConsumerWidget {
  const EntitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final entitiesAsync = ref.watch(entitiesStreamProvider);
    final eventTypesAsync = ref.watch(eventTypesStreamProvider);
    final enrollmentsAsync = ref.watch(protocolEnrollmentsStreamProvider);
    final appointmentsAsync = ref.watch(appointmentsStreamProvider);

    final entities = entitiesAsync.valueOrNull ?? const <Entity>[];
    final eventTypes = eventTypesAsync.valueOrNull ?? const <EventType>[];
    final enrollments =
        enrollmentsAsync.valueOrNull ?? const <ProtocolEnrollment>[];
    final appointments =
        appointmentsAsync.valueOrNull ?? const <Appointment>[];

    final Map<String, EventType> typesById = {
      for (final t in eventTypes) t.id: t,
    };
    final Map<String, ProtocolEnrollment> enrollmentsByEntity = {
      for (final e in enrollments) e.entityId: e,
    };

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: [
          Text(
            strings.entitiesHeader,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          for (final entity in entities)
            _EntityCard(
              entity: entity,
              eventType: typesById[entity.defaultEventTypeId],
              enrollment: enrollmentsByEntity[entity.id],
              entityAppointments: appointments
                  .where((a) => a.entityId == entity.id)
                  .toList(),
              strings: strings,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            _showAddEntityDialog(context, ref, eventTypes, strings),
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(strings.newEntityButton),
      ),
    );
  }

  Future<void> _showAddEntityDialog(
    BuildContext context,
    WidgetRef ref,
    List<EventType> eventTypes,
    AppStrings strings,
  ) async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String? selectedTypeId =
        eventTypes.isNotEmpty ? eventTypes.first.id : null;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(strings.newEntityButton),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: strings.isPt ? 'Nome Completo' : 'Full Name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      decoration: InputDecoration(
                        labelText: strings.isPt ? 'Telefone / WhatsApp' : 'Phone / WhatsApp',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (eventTypes.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: selectedTypeId,
                        decoration: InputDecoration(
                          labelText: strings.isPt ? 'Categoria Padrão' : 'Default Event Type',
                        ),
                        items: eventTypes
                            .map(
                              (et) => DropdownMenuItem(
                                value: et.id,
                                child: Text(et.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => selectedTypeId = v),
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
                    final entity = Entity(
                      id: 'entity_${DateTime.now().millisecondsSinceEpoch}',
                      name: name,
                      phone: phoneCtrl.text.trim().isEmpty
                          ? null
                          : phoneCtrl.text.trim(),
                      email: emailCtrl.text.trim().isEmpty
                          ? null
                          : emailCtrl.text.trim(),
                      defaultEventTypeId: selectedTypeId,
                    );
                    await ref
                        .read(schedulingRepositoryProvider)
                        .upsertEntity(entity);
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

class _EntityCard extends StatelessWidget {
  final Entity entity;
  final EventType? eventType;
  final ProtocolEnrollment? enrollment;
  final List<Appointment> entityAppointments;
  final AppStrings strings;

  const _EntityCard({
    required this.entity,
    required this.eventType,
    required this.enrollment,
    required this.entityAppointments,
    required this.strings,
  });

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(eventType?.colorHex ?? '#3F51B5');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.16),
                  foregroundColor: color,
                  child: Text(
                    entity.name.isNotEmpty ? entity.name[0].toUpperCase() : '?',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entity.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (entity.phone != null || entity.email != null)
                        Text(
                          [
                            if (entity.phone != null) entity.phone!,
                            if (entity.email != null) entity.email!,
                          ].join(' • '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (eventType != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      eventType!.name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (entity.customAvailabilityOverrides.isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: Colors.deepOrange.shade700,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${strings.customOverridesLabel}: ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.deepOrange.shade700,
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final w in entity.customAvailabilityOverrides)
                          Text(
                            '${strings.weekdayName(w.dayOfWeek, short: true)} '
                            '${w.startHour.toString().padLeft(2, '0')}:00–'
                            '${w.endHour.toString().padLeft(2, '0')}:00',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else
              Text(
                strings.defaultScheduleLabel,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (enrollment != null) ...[
              const Divider(height: 20),
              Row(
                children: [
                  Icon(Icons.science_outlined, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${enrollment!.protocolName} • '
                      '${entityAppointments.length}/${enrollment!.totalVisits} Visits '
                      '(Every ${enrollment!.cadenceDays}d ±${enrollment!.toleranceWindowDays}d)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: enrollment!.totalVisits > 0
                    ? (entityAppointments.length / enrollment!.totalVisits)
                        .clamp(0.0, 1.0)
                    : 0.0,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.timeline_rounded, size: 18),
                  label: Text(strings.viewProtocolRoadmap),
                  onPressed: () => _showRoadmapModal(context, color),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showRoadmapModal(BuildContext context, Color color) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.92,
          builder: (_, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  child: Text(
                    '${entity.name} • ${enrollment?.protocolName ?? ""}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: entityAppointments.length,
                    itemBuilder: (_, idx) {
                      final apt = entityAppointments[idx];
                      final visitNum = (apt.visitIndex ?? idx) + 1;
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: color.withValues(alpha: 0.15),
                          foregroundColor: color,
                          child: Text(
                            '$visitNum',
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
                        subtitle: Text(
                          strings.formatTimeRange(apt.timeRange),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.send_outlined, size: 18),
                          onPressed: () => ConfirmationSheet.show(
                            context,
                            appointment: apt,
                            entity: entity,
                            eventType: eventType,
                            strings: strings,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
