import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../domain/models/work_schedule.dart';
import '../providers/scheduling_providers.dart';

/// Tab 5: Settings, Localization (EN / PT-BR), Work Schedule Editor, and Connected Calendars.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final currentLang = ref.watch(appLanguageProvider);
    final use24Hour = ref.watch(use24HourFormatProvider);
    final workScheduleAsync = ref.watch(workScheduleStreamProvider);
    final calendarsAsync = ref.watch(externalCalendarsFutureProvider);
    final workSchedule = workScheduleAsync.valueOrNull ?? const WorkSchedule();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. Language & Time Format Section
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.language,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.languageSectionTitle,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedButton<AppLanguage>(
                  segments: AppLanguage.values
                      .map(
                        (lang) => ButtonSegment<AppLanguage>(
                          value: lang,
                          label: Text(lang.label),
                          icon: const Icon(Icons.translate, size: 18),
                        ),
                      )
                      .toList(),
                  selected: {currentLang},
                  onSelectionChanged: (selection) {
                    ref.read(appLanguageProvider.notifier).state =
                        selection.first;
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.use24HourLabel),
                  value: use24Hour,
                  onChanged: (value) {
                    ref.read(use24HourFormatProvider.notifier).state = value;
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 2. Primary Work Schedule Editor
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.work_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.workScheduleSectionTitle,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (int day = DateTime.monday;
                        day <= DateTime.sunday;
                        day++)
                      FilterChip(
                        label: Text(strings.weekdayName(day, short: true)),
                        selected: workSchedule.workDays.contains(day),
                        onSelected: (selected) async {
                          final updatedDays = Set<int>.from(
                            workSchedule.workDays,
                          );
                          if (selected) {
                            updatedDays.add(day);
                          } else if (updatedDays.length > 1) {
                            updatedDays.remove(day);
                          }
                          await ref
                              .read(schedulingRepositoryProvider)
                              .saveWorkSchedule(
                                WorkSchedule(
                                  workDays: updatedDays,
                                  startHour: workSchedule.startHour,
                                  startMinute: workSchedule.startMinute,
                                  endHour: workSchedule.endHour,
                                  endMinute: workSchedule.endMinute,
                                ),
                              );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.wb_sunny_outlined, size: 18),
                        label: Text(
                          '${strings.isPt ? "Início" : "Start"}: '
                          '${workSchedule.startHour.toString().padLeft(2, '0')}:'
                          '${workSchedule.startMinute.toString().padLeft(2, '0')}',
                        ),
                        onPressed: () async {
                          final nextStart =
                              workSchedule.startHour == 8 ? 9 : 8;
                          await ref
                              .read(schedulingRepositoryProvider)
                              .saveWorkSchedule(
                                WorkSchedule(
                                  workDays: workSchedule.workDays,
                                  startHour: nextStart,
                                  startMinute: 0,
                                  endHour: workSchedule.endHour,
                                  endMinute: workSchedule.endMinute,
                                ),
                              );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.nights_stay_outlined, size: 18),
                        label: Text(
                          '${strings.isPt ? "Fim" : "End"}: '
                          '${workSchedule.endHour.toString().padLeft(2, '0')}:'
                          '${workSchedule.endMinute.toString().padLeft(2, '0')}',
                        ),
                        onPressed: () async {
                          final nextEnd = workSchedule.endHour == 18 ? 17 : 18;
                          await ref
                              .read(schedulingRepositoryProvider)
                              .saveWorkSchedule(
                                WorkSchedule(
                                  workDays: workSchedule.workDays,
                                  startHour: workSchedule.startHour,
                                  startMinute: workSchedule.startMinute,
                                  endHour: nextEnd,
                                  endMinute: 0,
                                ),
                              );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 3. Connected Device Calendars & Two-Way Sync
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.connectedCalendarsSectionTitle,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                calendarsAsync.when(
                  data: (calendars) {
                    if (calendars.isEmpty) {
                      return Text(
                        strings.isPt
                            ? 'Nenhum calendário nativo detectado ainda. Clique em Sincronizar Agora para criar sub-calendários dedicados.'
                            : 'No device calendars detected yet. Tap Sync below to provision dedicated sub-calendars.',
                        style: Theme.of(context).textTheme.bodySmall,
                      );
                    }
                    return Column(
                      children: calendars
                          .map(
                            (cal) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.event_available,
                                size: 20,
                              ),
                              title: Text(cal.name),
                              subtitle: Text(
                                '${cal.accountName ?? "Local"} • ID: ${cal.id}',
                              ),
                              trailing: Icon(
                                cal.isReadOnly
                                    ? Icons.lock_outline
                                    : Icons.sync,
                                size: 18,
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  ),
                  error: (e, _) => Text('Error: $e'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final result = await ref
                          .read(calendarSyncServiceProvider)
                          .syncAll();
                      ref.invalidate(externalCalendarsFutureProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Synced: ${result.pushedAppointmentsCount} pushed, '
                              '${result.updatedAppointmentsCount} updated, '
                              '${result.createdCalendarsCount} sub-calendars created.',
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.sync),
                    label: Text(strings.syncNowButton),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await ref.read(demoSeedServiceProvider).resetAndSeed();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(strings.demoResetSuccess)),
                        );
                      }
                    },
                    icon: const Icon(Icons.restore),
                    label: Text(strings.resetDemoButton),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
