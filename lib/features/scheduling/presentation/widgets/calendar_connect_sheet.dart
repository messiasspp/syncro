import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/syncro_theme.dart';
import '../../domain/models/external_calendar.dart';
import '../providers/scheduling_providers.dart';

/// Frosted glassmorphic bottom sheet for connecting, switching, and syncing
/// with the user's Google Calendar / local device calendar accounts.
class CalendarConnectSheet extends ConsumerWidget {
  const CalendarConnectSheet({super.key});

  static Future<void> show(BuildContext context) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CalendarConnectSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final strings = ref.watch(appStringsProvider);
    final calendarsAsync = ref.watch(externalCalendarsFutureProvider);
    final activePrimary = ref.watch(activePrimaryCalendarProvider);
    final showExternalInAgenda = ref.watch(showExternalEventsInAgendaProvider);
    final eventTypes =
        ref.watch(eventTypesStreamProvider).valueOrNull ?? const [];

    final calendars = calendarsAsync.valueOrNull ?? const <ExternalCalendar>[];
    final userCalendars = calendars
        .where((c) => !c.name.startsWith('Syncro') && c.accountName != 'Syncro')
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.76,
      maxChildSize: 0.94,
      minChildSize: 0.48,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                color: isDark
                    ? SyncroColors.darkSurface.withValues(alpha: 0.94)
                    : Colors.white.withValues(alpha: 0.96),
                border: Border(
                  top: BorderSide(
                    color:
                        SyncroColors.clinicalEmerald.withValues(alpha: 0.55),
                    width: 1.6,
                  ),
                ),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.24),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: SyncroColors.clinicalEmerald
                              .withValues(alpha: 0.16),
                        ),
                        child: const Icon(
                          Icons.event_available_rounded,
                          color: SyncroColors.clinicalEmerald,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.isPt
                                  ? 'Google Calendar e Agenda Local'
                                  : 'Google & Local Calendar Hub',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              activePrimary != null
                                  ? (strings.isPt
                                      ? 'Conectado: ${activePrimary.name}'
                                      : 'Connected: ${activePrimary.name}')
                                  : (strings.isPt
                                      ? 'Nenhuma conta detectada'
                                      : 'No calendar account detected'),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: SyncroColors.clinicalEmerald,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SwitchListTile.adaptive(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    tileColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.08),
                    title: Text(
                      strings.isPt
                          ? 'Exibir Eventos do Google Calendar na Agenda'
                          : 'Show Google Calendar Events in Agenda',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      strings.isPt
                          ? 'Mostra seus compromissos reais na Linha do Tempo, Mês e Semana'
                          : 'Displays your real external events in Timeline, Month & Week views',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    value: showExternalInAgenda,
                    onChanged: (v) {
                      HapticFeedback.selectionClick();
                      ref
                          .read(showExternalEventsInAgendaProvider.notifier)
                          .state = v;
                      ref.invalidate(externalCalendarEventsProvider);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    strings.isPt
                        ? 'Selecionar Conta Principal (Para Novos Agendamentos)'
                        : 'Select Primary Calendar Account (For New Bookings)',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (userCalendars.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.lock_open_rounded),
                        label: Text(
                          strings.isPt
                              ? 'Solicitar Permissão de Calendário'
                              : 'Request Calendar Permission',
                        ),
                        onPressed: () async {
                          await ref
                              .read(calendarClientProvider)
                              .requestPermissions();
                          ref.invalidate(externalCalendarsFutureProvider);
                          ref.invalidate(externalCalendarEventsProvider);
                        },
                      ),
                    )
                  else
                    for (final cal in userCalendars)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: activePrimary?.id == cal.id
                              ? SyncroColors.clinicalEmerald
                                  .withValues(alpha: 0.14)
                              : Colors.transparent,
                          border: Border.all(
                            color: activePrimary?.id == cal.id
                                ? SyncroColors.clinicalEmerald
                                : Theme.of(context).colorScheme.outlineVariant,
                            width: activePrimary?.id == cal.id ? 1.5 : 1.0,
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            activePrimary?.id == cal.id
                                ? Icons.check_circle_rounded
                                : Icons.calendar_today_rounded,
                            color: activePrimary?.id == cal.id
                                ? SyncroColors.clinicalEmerald
                                : null,
                          ),
                          title: Text(
                            cal.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            '${cal.accountName ?? "Local"} • ${cal.isReadOnly ? (strings.isPt ? "Somente Leitura" : "Read-Only") : (strings.isPt ? "Leitura e Escrita" : "Read & Write")}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: cal.isReadOnly
                              ? null
                              : () async {
                                  HapticFeedback.mediumImpact();
                                  ref
                                      .read(selectedPrimaryCalendarIdProvider
                                          .notifier)
                                      .state = cal.id;
                                  // Route all existing Groups to this calendar so bookings go straight to Google Calendar
                                  final repo =
                                      ref.read(schedulingRepositoryProvider);
                                  for (final et in eventTypes) {
                                    await repo.upsertEventType(
                                      et.copyWith(calendarMappingId: cal.id),
                                    );
                                  }
                                  ref.invalidate(eventTypesStreamProvider);
                                  ref.invalidate(externalCalendarEventsProvider);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          strings.isPt
                                              ? 'Conta principal definida: ${cal.name}!'
                                              : 'Primary calendar set to ${cal.name}!',
                                        ),
                                      ),
                                    );
                                  }
                                },
                        ),
                      ),
                  const Divider(height: 24),
                  FilledButton.icon(
                    icon: const Icon(Icons.sync_rounded),
                    label: Text(
                      strings.isPt
                          ? 'Sincronizar Tudo com Google Calendar Agora'
                          : 'Sync All with Google Calendar Now',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () async {
                      HapticFeedback.mediumImpact();
                      // Ensure existing Groups without a mapping use the primary calendar
                      if (activePrimary != null) {
                        final repo = ref.read(schedulingRepositoryProvider);
                        for (final et in eventTypes) {
                          if (et.calendarMappingId == null) {
                            await repo.upsertEventType(
                              et.copyWith(calendarMappingId: activePrimary.id),
                            );
                          }
                        }
                      }
                      final result =
                          await ref.read(calendarSyncServiceProvider).syncAll();
                      ref.invalidate(externalCalendarsFutureProvider);
                      ref.invalidate(externalCalendarEventsProvider);
                      ref.invalidate(calendarConflictsProvider);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Synced: ${result.pushedAppointmentsCount} pushed, '
                              '${result.updatedAppointmentsCount} updated.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(
                      Icons.cleaning_services_rounded,
                      size: 18,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SyncroColors.coralAlert,
                      side: BorderSide(
                        color: SyncroColors.coralAlert.withValues(alpha: 0.55),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    label: Text(
                      strings.isPt
                          ? 'Usar Apenas Minha Agenda Real (Limpar Demo)'
                          : 'Use My Real Calendar Only (Clear Demo Data)',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    onPressed: () async {
                      HapticFeedback.heavyImpact();
                      await ref
                          .read(demoSeedServiceProvider)
                          .clearToCleanSlate();
                      ref.invalidate(eventTypesStreamProvider);
                      ref.invalidate(entitiesStreamProvider);
                      ref.invalidate(protocolEnrollmentsStreamProvider);
                      ref.invalidate(appointmentsStreamProvider);
                      ref.invalidate(externalCalendarEventsProvider);
                      ref.invalidate(calendarConflictsProvider);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(strings.startFreshSuccess)),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
