import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/syncro_theme.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../domain/models/appointment.dart';
import '../../domain/models/entity.dart';
import '../../domain/models/event_type.dart';
import '../../domain/models/protocol_enrollment.dart';
import '../providers/scheduling_providers.dart';
import '../widgets/confirmation_sheet.dart';

/// Tab 3: Glassmorphic Directory of Participants (Friends & Clinical Patients)
/// with 24-Visit Protocol Heatmap & Roadmaps.
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

    final eventTypeById = {for (final et in eventTypes) et.id: et};
    final enrollmentByEntityId = {for (final p in enrollments) p.entityId: p};
    final topPadding = MediaQuery.of(context).padding.top + kToolbarHeight + 14;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 155),
      children: [
        Text(
          strings.entitiesHeader,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
        ),
        const SizedBox(height: 14),
        for (int i = 0; i < entities.length; i++)
          StaggeredReveal(
            index: i,
            child: _EntityGlassCard(
              entity: entities[i],
              eventType: eventTypeById[entities[i].defaultEventTypeId],
              enrollment: enrollmentByEntityId[entities[i].id],
              entityAppointments: appointments
                  .where((a) => a.entityId == entities[i].id)
                  .toList(),
              strings: strings,
            ),
          ),
      ],
    );
  }

  static Future<void> showCreateEntityDialog(
    BuildContext context,
    WidgetRef ref,
    AppStrings strings,
    List<EventType> eventTypes,
  ) async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String? selectedEventTypeId =
        eventTypes.isNotEmpty ? eventTypes.first.id : null;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: Text(strings.newEntityButton),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText:
                            strings.isPt ? 'Nome Completo' : 'Full Name',
                        hintText: 'e.g. Alex / Patient 103',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (eventTypes.isNotEmpty)
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: selectedEventTypeId,
                        decoration: InputDecoration(
                          labelText: strings.isPt
                              ? 'Categoria Padrão'
                              : 'Default Event Type',
                        ),
                        items: eventTypes
                            .map(
                              (et) => DropdownMenuItem(
                                value: et.id,
                                child: Text(et.name),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setModalState(() => selectedEventTypeId = val),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'WhatsApp / Phone',
                        hintText: '+1-555-0199',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'participant@example.com',
                      ),
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
                    if (name.isEmpty || selectedEventTypeId == null) return;
                    final entity = Entity(
                      id: 'entity_${DateTime.now().millisecondsSinceEpoch}',
                      name: name,
                      defaultEventTypeId: selectedEventTypeId!,
                      phone: phoneCtrl.text.trim().isEmpty
                          ? null
                          : phoneCtrl.text.trim(),
                      email: emailCtrl.text.trim().isEmpty
                          ? null
                          : emailCtrl.text.trim(),
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

class _EntityGlassCard extends StatelessWidget {
  final Entity entity;
  final EventType? eventType;
  final ProtocolEnrollment? enrollment;
  final List<Appointment> entityAppointments;
  final AppStrings strings;

  const _EntityGlassCard({
    required this.entity,
    required this.eventType,
    required this.enrollment,
    required this.entityAppointments,
    required this.strings,
  });

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(eventType?.colorHex ?? '#6366F1');
    final initials = entity.name
        .trim()
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();

    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      borderColor: color.withValues(alpha: 0.36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color,
                      color.withValues(alpha: 0.65),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.40),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
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
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      '${eventType?.name ?? entity.defaultEventTypeId}'
                      '${entity.phone != null ? " • ${entity.phone}" : ""}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
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
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Text(
                  '${entityAppointments.length} ${strings.isPt ? "visitas" : "visits"}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (entity.customAvailabilityOverrides.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: SyncroColors.amberSuggested.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: SyncroColors.amberSuggested.withValues(alpha: 0.38),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: SyncroColors.amberSuggested,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${strings.customOverridesLabel}: '
                      '${entity.customAvailabilityOverrides.map((w) => "${strings.weekdayName(w.dayOfWeek, short: true)} ${w.startHour.toString().padLeft(2, '0')}:00–${w.endHour.toString().padLeft(2, '0')}:00").join(", ")}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: SyncroColors.amberSuggested,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              strings.defaultScheduleLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (enrollment != null) ...[
            const Divider(height: 22),
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
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: enrollment!.totalVisits > 0
                    ? (entityAppointments.length / enrollment!.totalVisits)
                        .clamp(0.0, 1.0)
                    : 0.0,
                minHeight: 6,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.grid_view_rounded, size: 17),
                label: Text(strings.viewProtocolRoadmap),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => _showRoadmapModal(context, color),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showRoadmapModal(BuildContext context, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          maxChildSize: 0.94,
          builder: (_, scrollController) {
            return ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border(
                      top: BorderSide(
                        color: color.withValues(alpha: 0.45),
                        width: 1.4,
                      ),
                    ),
                    color: isDark
                        ? SyncroColors.darkSurface.withValues(alpha: 0.92)
                        : Colors.white.withValues(alpha: 0.94),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          margin: const EdgeInsets.only(top: 12, bottom: 12),
                          decoration: BoxDecoration(
                            color: (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.24),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 4,
                        ),
                        child: Text(
                          '${entity.name} • ${enrollment?.protocolName ?? ""}',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                      // 24-Visit Visual Heatmap Matrix
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (int i = 0;
                                i < entityAppointments.length;
                                i++)
                              Container(
                                width: 32,
                                height: 26,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color: color.withValues(alpha: 0.45),
                                  ),
                                ),
                                child: Text(
                                  '#${i + 1}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: color,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
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
                                backgroundColor: color.withValues(alpha: 0.18),
                                foregroundColor: color,
                                child: Text(
                                  '$visitNum',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              title: Text(
                                strings.formatDateHeader(apt.timeRange.start),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                strings.formatTimeRange(apt.timeRange),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.send_outlined,
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
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
