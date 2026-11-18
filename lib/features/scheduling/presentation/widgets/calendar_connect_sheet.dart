import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/syncro_theme.dart';
import '../../domain/models/event_type.dart';
import '../../domain/models/external_calendar.dart';
import '../providers/scheduling_providers.dart';
import 'calendar_cleanup_sheet.dart';

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
    final cloudEmail = ref.watch(googleCloudConnectedEmailProvider);
    final eventTypes =
        ref.watch(eventTypesStreamProvider).valueOrNull ?? const [];

    final calendars = calendarsAsync.valueOrNull ?? const <ExternalCalendar>[];
    final userCalendars = calendars
        .where((c) =>
            c.accountName != 'Syncro' &&
            c.accountName != 'Syncro Local' &&
            !c.name.startsWith('Syncro —'))
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
                  const SizedBox(height: 12),
                  _GoogleCloudApiCard(
                    cloudEmail: cloudEmail,
                    preferredEmail:
                        activePrimary?.accountName ?? activePrimary?.name,
                    eventTypes: eventTypes,
                    strings: strings,
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
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(
                      Icons.delete_sweep_rounded,
                      size: 18,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SyncroColors.amberSuggested,
                      side: BorderSide(
                        color:
                            SyncroColors.amberSuggested.withValues(alpha: 0.55),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    label: Text(
                      strings.isPt
                          ? 'Limpar Calendários e Eventos do Syncro'
                          : 'Clean Syncro Calendars & Events',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      CalendarCleanupSheet.show(context);
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

class _GoogleCloudApiCard extends ConsumerWidget {
  final String? cloudEmail;
  final String? preferredEmail;
  final List<EventType> eventTypes;
  final AppStrings strings;

  const _GoogleCloudApiCard({
    required this.cloudEmail,
    required this.preferredEmail,
    required this.eventTypes,
    required this.strings,
  });

  static const _packageName = 'com.example.syncro';
  static const _debugSha1 =
      'F4:24:37:7F:49:44:6B:BF:24:1C:37:82:BE:79:0C:42:7F:AF:AA:0A';

  Future<void> _provisionGroupCalendars(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final syncService = ref.read(calendarSyncServiceProvider);
    final defaultId = await syncService.ensureDefaultSyncroCalendar();
    if (defaultId != null) {
      ref.read(selectedPrimaryCalendarIdProvider.notifier).state = defaultId;
    }
    int provisioned = 0;
    for (final et in eventTypes) {
      await syncService.ensureDedicatedCalendarForEventType(et);
      provisioned++;
    }
    ref.invalidate(externalCalendarsFutureProvider);
    ref.invalidate(externalCalendarEventsProvider);
    ref.invalidate(eventTypesStreamProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.isPt
                ? 'Calendário padrão "Syncro" ativo e $provisioned grupo(s) sincronizado(s)!'
                : 'Default "Syncro" calendar active & synced $provisioned group(s)!',
          ),
        ),
      );
    }
  }

  Future<void> _showOAuthSetupDialog(
    BuildContext context,
    WidgetRef ref, {
    String? errorDetail,
  }) async {
    final tokenCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            const Icon(
              Icons.cloud_done_rounded,
              color: SyncroColors.electricIndigo,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                strings.isPt
                    ? 'Configuração OAuth / Token Google Cloud'
                    : 'Google Cloud OAuth / Token Setup',
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (errorDetail != null) ...[
                Text(
                  errorDetail,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: SyncroColors.coralAlert,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                strings.isPt
                    ? 'Para usar o login automático sem token manual, adicione este ID Android no Google Cloud Console:'
                    : 'For 1-tap Google Sign-In, register this Android OAuth client in Google Cloud Console:',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: const Text(
                  'Pkg: $_packageName',
                  style: TextStyle(fontSize: 11.5),
                ),
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: _packageName));
                },
              ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                icon: const Icon(Icons.fingerprint_rounded, size: 15),
                label: Text(
                  'SHA-1: ${_debugSha1.substring(0, 17)}...',
                  style: const TextStyle(fontSize: 11.5),
                ),
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: _debugSha1));
                },
              ),
              const Divider(height: 20),
              Text(
                strings.isPt
                    ? 'Ou cole um Access Token OAuth2 diretamente (escopo calendar):'
                    : 'Or paste an OAuth2 Access Token directly (calendar scope):',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: tokenCtrl,
                decoration: InputDecoration(
                  hintText: 'ya29....',
                  labelText: 'Access Token',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(strings.cancelAction),
          ),
          FilledButton(
            onPressed: () async {
              final token = tokenCtrl.text.trim();
              if (token.isEmpty) return;
              final cloudSvc = ref.read(googleCloudCalendarServiceProvider);
              cloudSvc.setManualAccessToken(
                token,
                email: preferredEmail,
              );
              ref.read(googleCloudConnectedEmailProvider.notifier).state =
                  cloudSvc.signedInEmail;
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (context.mounted) {
                await _provisionGroupCalendars(context, ref);
              }
            },
            child: Text(
              strings.isPt ? 'Ativar & Criar Calendários' : 'Activate & Sync',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = cloudEmail != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: (isConnected
                ? SyncroColors.clinicalEmerald
                : SyncroColors.electricIndigo)
            .withValues(alpha: 0.10),
        border: Border.all(
          color: (isConnected
                  ? SyncroColors.clinicalEmerald
                  : SyncroColors.electricIndigo)
              .withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isConnected
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_upload_rounded,
                color: isConnected
                    ? SyncroColors.clinicalEmerald
                    : SyncroColors.electricIndigo,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isConnected
                      ? (strings.isPt
                          ? 'Google Cloud API Ativa ($cloudEmail)'
                          : 'Google Cloud API Active ($cloudEmail)')
                      : (strings.isPt
                          ? 'Google Cloud API (Calendário Padrão "Syncro")'
                          : 'Google Cloud API (Default "Syncro" Calendar)'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isConnected
                ? (strings.isPt
                    ? 'Calendário padrão "Syncro" ativo na nuvem. Novos Grupos usam ele automaticamente (ou escolha outro em Rotear Conta).'
                    : 'Default "Syncro" cloud calendar is active. New Groups use it automatically (or choose any calendar in Route Account).')
                : (strings.isPt
                    ? 'Conecte para criar automaticamente o calendário padrão "Syncro" direto na sua conta Google (Celular e Web).'
                    : 'Connect to automatically create the default "Syncro" calendar in your Google account across Mobile & Web.'),
            style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 10),
          if (isConnected)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.create_new_folder_rounded, size: 16),
                    label: Text(
                      strings.isPt
                          ? 'Garantir Calendário Padrão "Syncro"'
                          : 'Ensure Default "Syncro" Calendar',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onPressed: () => _provisionGroupCalendars(context, ref),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    await ref.read(googleCloudCalendarServiceProvider).signOut();
                    ref.read(googleCloudConnectedEmailProvider.notifier).state =
                        null;
                    ref.invalidate(externalCalendarsFutureProvider);
                  },
                  child: Text(strings.isPt ? 'Sair' : 'Sign out'),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.login_rounded, size: 17),
                    label: Text(
                      strings.isPt
                          ? 'Conectar Google Cloud API'
                          : 'Connect Google Cloud API',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onPressed: () async {
                      HapticFeedback.mediumImpact();
                      final cloudSvc =
                          ref.read(googleCloudCalendarServiceProvider);
                      try {
                        final email = await cloudSvc.signInInteractive(
                          preferredEmail: preferredEmail,
                        );
                        if (email != null) {
                          ref
                              .read(googleCloudConnectedEmailProvider.notifier)
                              .state = email;
                          if (context.mounted) {
                            await _provisionGroupCalendars(context, ref);
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          await _showOAuthSetupDialog(
                            context,
                            ref,
                            errorDetail: e.toString(),
                          );
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _showOAuthSetupDialog(context, ref),
                  child: Text(
                    strings.isPt ? 'Token / OAuth' : 'Token / OAuth',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
