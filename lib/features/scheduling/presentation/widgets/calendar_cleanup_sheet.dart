import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/syncro_theme.dart';
import '../../domain/models/external_calendar.dart';
import '../../domain/services/calendar_sync_service.dart';
import '../providers/scheduling_providers.dart';

/// Interactive frosted-glass sheet to inspect and delete all hidden local
/// calendars and Syncro-created events from the device & Google Calendar.
class CalendarCleanupSheet extends ConsumerStatefulWidget {
  const CalendarCleanupSheet({super.key});

  static Future<void> show(BuildContext context) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CalendarCleanupSheet(),
    );
  }

  @override
  ConsumerState<CalendarCleanupSheet> createState() =>
      _CalendarCleanupSheetState();
}

class _CalendarCleanupSheetState extends ConsumerState<CalendarCleanupSheet> {
  bool _isScanning = true;
  bool _isCleaning = false;
  String? _errorMessage;
  SyncroCalendarAudit? _audit;
  SyncroCleanupResult? _lastResult;

  final Set<String> _selectedCalendarIds = {};
  final Set<String> _selectedEventKeys = {};

  @override
  void initState() {
    super.initState();
    _runAudit();
  }

  String _eventKey(ExternalCalendarEvent evt) =>
      '${evt.calendarId}::${evt.externalEventId ?? evt.timeRange.start.millisecondsSinceEpoch}';

  Future<void> _runAudit() async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });
    try {
      final audit = await ref
          .read(calendarSyncServiceProvider)
          .auditSyncroCalendarData();
      if (!mounted) return;
      setState(() {
        _audit = audit;
        _selectedCalendarIds
          ..clear()
          ..addAll(audit.syncroCalendars.map((c) => c.id));
        _selectedEventKeys
          ..clear()
          ..addAll(audit.syncroEventsInUserCalendars.map(_eventKey));
        _isScanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isScanning = false;
      });
    }
  }

  Future<void> _executeCleanup() async {
    final audit = _audit;
    if (audit == null || _isCleaning) return;

    final strings = ref.read(appStringsProvider);
    final eventsToDelete = audit.syncroEventsInUserCalendars
        .where((e) => _selectedEventKeys.contains(_eventKey(e)))
        .toList();
    final calIdsToDelete = _selectedCalendarIds.toList();

    if (calIdsToDelete.isEmpty && eventsToDelete.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(
              Icons.delete_sweep_rounded,
              color: SyncroColors.coralAlert,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                strings.isPt
                    ? 'Limpar Dados do Syncro?'
                    : 'Clean Syncro Calendar Data?',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          strings.isPt
              ? 'Isso removerá permanentemente ${calIdsToDelete.length} calendário(s) local(is) e ${eventsToDelete.length} evento(s) criado(s) pelo Syncro do seu aparelho / Google Calendar.'
              : 'This will permanently delete ${calIdsToDelete.length} local calendar(s) and ${eventsToDelete.length} Syncro-created event(s) from your device / Google Calendar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(strings.cancelAction),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SyncroColors.coralAlert,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              strings.isPt ? 'Sim, Limpar' : 'Yes, Clean All',
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isCleaning = true);
    HapticFeedback.heavyImpact();

    try {
      final result = await ref
          .read(calendarSyncServiceProvider)
          .cleanSyncroCalendarData(
            calendarIdsToDelete: calIdsToDelete,
            eventsToDelete: eventsToDelete,
          );

      ref.invalidate(externalCalendarsFutureProvider);
      ref.invalidate(externalCalendarEventsProvider);
      ref.invalidate(calendarConflictsProvider);
      ref.invalidate(eventTypesStreamProvider);
      ref.invalidate(appointmentsStreamProvider);

      if (!mounted) return;
      setState(() {
        _lastResult = result;
        _isCleaning = false;
      });
      await _runAudit();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isCleaning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final strings = ref.watch(appStringsProvider);
    final audit = _audit;

    final totalSelected =
        _selectedCalendarIds.length + _selectedEventKeys.length;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
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
                    color: SyncroColors.coralAlert.withValues(alpha: 0.55),
                    width: 1.6,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
                                color: SyncroColors.coralAlert
                                    .withValues(alpha: 0.16),
                              ),
                              child: const Icon(
                                Icons.delete_sweep_rounded,
                                color: SyncroColors.coralAlert,
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
                                        ? 'Limpeza de Calendários Syncro'
                                        : 'Syncro Calendar Cleanup',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  Text(
                                    strings.isPt
                                        ? 'Remove calendários locais ocultos e eventos antigos do Syncro'
                                        : 'Remove hidden local Syncro calendars & Syncro-created events',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: strings.isPt ? 'Reescanear' : 'Rescan',
                              onPressed: _isScanning ? null : _runAudit,
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (_lastResult != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: SyncroColors.clinicalEmerald
                                  .withValues(alpha: 0.14),
                              border: Border.all(
                                color: SyncroColors.clinicalEmerald
                                    .withValues(alpha: 0.45),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: SyncroColors.clinicalEmerald,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    strings.isPt
                                        ? 'Limpeza concluída: ${_lastResult!.deletedCalendarsCount} calendário(s) e ${_lastResult!.deletedEventsCount} evento(s) removidos.'
                                        : 'Cleanup complete: removed ${_lastResult!.deletedCalendarsCount} calendar(s) and ${_lastResult!.deletedEventsCount} event(s).',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: SyncroColors.clinicalEmerald,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: SyncroColors.coralAlert
                                  .withValues(alpha: 0.14),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: SyncroColors.coralAlert,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_isScanning)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Column(
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 14),
                                Text(
                                  strings.isPt
                                      ? 'Escaneando calendários do dispositivo...'
                                      : 'Scanning device calendars...',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        else if (audit != null && audit.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: SyncroColors.clinicalEmerald
                                  .withValues(alpha: 0.10),
                              border: Border.all(
                                color: SyncroColors.clinicalEmerald
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.verified_rounded,
                                  color: SyncroColors.clinicalEmerald,
                                  size: 40,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  strings.isPt
                                      ? 'Tudo limpo!'
                                      : 'Everything is clean!',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  strings.isPt
                                      ? 'Nenhum calendário local oculto ou evento criado pelo Syncro foi encontrado.'
                                      : 'No hidden Syncro local calendars or Syncro-created events were found.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ],
                            ),
                          )
                        else if (audit != null) ...[
                          // 1. Syncro Local Calendars
                          _SectionHeader(
                            title: strings.isPt
                                ? 'Calendários Locais do Syncro (${audit.syncroCalendars.length})'
                                : 'Syncro Local Calendars (${audit.syncroCalendars.length})',
                            subtitle: strings.isPt
                                ? 'Estes calendários existem apenas no aparelho (ocultos no Google Calendar e ausentes na Web).'
                                : 'Offline device-only calendars (hidden in mobile Google Calendar & never synced to Web).',
                            allSelected: audit.syncroCalendars.isNotEmpty &&
                                audit.syncroCalendars.every(
                                    (c) => _selectedCalendarIds.contains(c.id)),
                            onToggleAll: audit.syncroCalendars.isEmpty
                                ? null
                                : (select) {
                                    setState(() {
                                      for (final c in audit.syncroCalendars) {
                                        if (select) {
                                          _selectedCalendarIds.add(c.id);
                                        } else {
                                          _selectedCalendarIds.remove(c.id);
                                        }
                                      }
                                    });
                                  },
                            strings: strings,
                          ),
                          const SizedBox(height: 8),
                          if (audit.syncroCalendars.isEmpty)
                            _EmptyNote(
                              text: strings.isPt
                                  ? 'Nenhum calendário local do Syncro encontrado.'
                                  : 'No Syncro local calendars found.',
                            )
                          else
                            for (final cal in audit.syncroCalendars)
                              CheckboxListTile(
                                dense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                value: _selectedCalendarIds.contains(cal.id),
                                activeColor: SyncroColors.coralAlert,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedCalendarIds.add(cal.id);
                                    } else {
                                      _selectedCalendarIds.remove(cal.id);
                                    }
                                  });
                                },
                                title: Text(
                                  cal.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  'ID: ${cal.id} • ${cal.accountName ?? "LOCAL"}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                          const SizedBox(height: 16),

                          // 2. Syncro Events inside User Google/Device Calendars
                          _SectionHeader(
                            title: strings.isPt
                                ? 'Eventos do Syncro no Google Calendar (${audit.syncroEventsInUserCalendars.length})'
                                : 'Syncro Events in Google Calendar (${audit.syncroEventsInUserCalendars.length})',
                            subtitle: strings.isPt
                                ? 'Eventos gravados pelo Syncro dentro das suas contas reais.'
                                : 'Events written by Syncro inside your connected cloud/device calendars.',
                            allSelected:
                                audit.syncroEventsInUserCalendars.isNotEmpty &&
                                    audit.syncroEventsInUserCalendars.every(
                                      (e) => _selectedEventKeys
                                          .contains(_eventKey(e)),
                                    ),
                            onToggleAll:
                                audit.syncroEventsInUserCalendars.isEmpty
                                    ? null
                                    : (select) {
                                        setState(() {
                                          for (final e in audit
                                              .syncroEventsInUserCalendars) {
                                            final k = _eventKey(e);
                                            if (select) {
                                              _selectedEventKeys.add(k);
                                            } else {
                                              _selectedEventKeys.remove(k);
                                            }
                                          }
                                        });
                                      },
                            strings: strings,
                          ),
                          const SizedBox(height: 8),
                          if (audit.syncroEventsInUserCalendars.isEmpty)
                            _EmptyNote(
                              text: strings.isPt
                                  ? 'Nenhum evento do Syncro encontrado nas contas conectadas.'
                                  : 'No Syncro-created events found in connected calendars.',
                            )
                          else
                            for (final evt in audit.syncroEventsInUserCalendars)
                              CheckboxListTile(
                                dense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                value: _selectedEventKeys
                                    .contains(_eventKey(evt)),
                                activeColor: SyncroColors.coralAlert,
                                onChanged: (val) {
                                  setState(() {
                                    final k = _eventKey(evt);
                                    if (val == true) {
                                      _selectedEventKeys.add(k);
                                    } else {
                                      _selectedEventKeys.remove(k);
                                    }
                                  });
                                },
                                title: Text(
                                  evt.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  DateFormat('EEE, MMM d yyyy • HH:mm')
                                      .format(evt.timeRange.start),
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),

                          // 3. Other Local Calendars (unchecked by default for safety)
                          if (audit.otherLocalCalendars.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _SectionHeader(
                              title: strings.isPt
                                  ? 'Outros Calendários Locais (${audit.otherLocalCalendars.length})'
                                  : 'Other Local Calendars (${audit.otherLocalCalendars.length})',
                              subtitle: strings.isPt
                                  ? 'Desmarcados por segurança. Marque apenas se reconhecer como antigo.'
                                  : 'Unchecked for safety. Select only if you recognize them as leftover local calendars.',
                              allSelected: audit.otherLocalCalendars.every(
                                  (c) => _selectedCalendarIds.contains(c.id)),
                              onToggleAll: (select) {
                                setState(() {
                                  for (final c in audit.otherLocalCalendars) {
                                    if (select) {
                                      _selectedCalendarIds.add(c.id);
                                    } else {
                                      _selectedCalendarIds.remove(c.id);
                                    }
                                  }
                                });
                              },
                              strings: strings,
                            ),
                            const SizedBox(height: 8),
                            for (final cal in audit.otherLocalCalendars)
                              CheckboxListTile(
                                dense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                value: _selectedCalendarIds.contains(cal.id),
                                activeColor: SyncroColors.amberSuggested,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedCalendarIds.add(cal.id);
                                    } else {
                                      _selectedCalendarIds.remove(cal.id);
                                    }
                                  });
                                },
                                title: Text(
                                  cal.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  'ID: ${cal.id} • ${cal.accountName ?? "LOCAL"}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: SyncroColors.coralAlert,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed:
                              (_isScanning || _isCleaning || totalSelected == 0)
                                  ? null
                                  : _executeCleanup,
                          icon: _isCleaning
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.delete_forever_rounded),
                          label: Text(
                            strings.isPt
                                ? 'Limpar Selecionados ($totalSelected)'
                                : 'Clean Selected Data ($totalSelected)',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
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

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool allSelected;
  final ValueChanged<bool>? onToggleAll;
  final AppStrings strings;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.allSelected,
    required this.onToggleAll,
    required this.strings,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ],
          ),
        ),
        if (onToggleAll != null)
          TextButton(
            onPressed: () => onToggleAll!(!allSelected),
            child: Text(
              allSelected
                  ? (strings.isPt ? 'Desmarcar' : 'Unselect')
                  : (strings.isPt ? 'Selecionar Tudo' : 'Select All'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final String text;
  const _EmptyNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).textTheme.bodySmall?.color,
        ),
      ),
    );
  }
}
