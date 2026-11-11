import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/syncro_theme.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../domain/models/work_schedule.dart';
import '../providers/scheduling_providers.dart';

/// Tab 5: Glassmorphic Control Center Settings (Theme, Localization, Work Schedule, Connected Calendars).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final currentLang = ref.watch(appLanguageProvider);
    final use24Hour = ref.watch(use24HourFormatProvider);
    final themeMode = ref.watch(themeModeProvider);
    final workScheduleAsync = ref.watch(workScheduleStreamProvider);
    final calendarsAsync = ref.watch(externalCalendarsFutureProvider);
    final workSchedule = workScheduleAsync.valueOrNull ?? const WorkSchedule();
    final topPadding = MediaQuery.of(context).padding.top + kToolbarHeight + 14;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 115),
      children: [
        // 1. Visual Appearance & Theme Selector
        StaggeredReveal(
          index: 0,
          child: GlassContainer(
            padding: const EdgeInsets.all(16),
            borderRadius: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.palette_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.appearanceSectionTitle,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ThemeOptionCard(
                        icon: Icons.dark_mode_rounded,
                        label: strings.darkGlassThemeLabel,
                        isSelected: themeMode == ThemeMode.dark,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ref.read(themeModeProvider.notifier).state =
                              ThemeMode.dark;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ThemeOptionCard(
                        icon: Icons.light_mode_rounded,
                        label: strings.lightGlassThemeLabel,
                        isSelected: themeMode == ThemeMode.light,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ref.read(themeModeProvider.notifier).state =
                              ThemeMode.light;
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 2. Language & Time Format Section
        StaggeredReveal(
          index: 1,
          child: GlassContainer(
            padding: const EdgeInsets.all(16),
            borderRadius: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.language_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.languageSectionTitle,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
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
                          icon: const Icon(Icons.translate_rounded, size: 17),
                        ),
                      )
                      .toList(),
                  selected: {currentLang},
                  onSelectionChanged: (selection) {
                    HapticFeedback.selectionClick();
                    ref.read(appLanguageProvider.notifier).state =
                        selection.first;
                  },
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    strings.use24HourLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  value: use24Hour,
                  onChanged: (value) {
                    HapticFeedback.selectionClick();
                    ref.read(use24HourFormatProvider.notifier).state = value;
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 3. Primary Work Schedule Editor & 24h Boundary Visualizer
        StaggeredReveal(
          index: 2,
          child: GlassContainer(
            padding: const EdgeInsets.all(16),
            borderRadius: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.work_outline_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.workScheduleSectionTitle,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (int day = DateTime.monday;
                        day <= DateTime.sunday;
                        day++)
                      _WeekdayOrb(
                        label: strings.weekdayName(day, short: true),
                        isSelected: workSchedule.workDays.contains(day),
                        onTap: () async {
                          HapticFeedback.selectionClick();
                          final updatedDays = Set<int>.from(
                            workSchedule.workDays,
                          );
                          if (updatedDays.contains(day)) {
                            if (updatedDays.length > 1) {
                              updatedDays.remove(day);
                            }
                          } else {
                            updatedDays.add(day);
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
                          HapticFeedback.selectionClick();
                          final nextStart = workSchedule.startHour == 8 ? 9 : 8;
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
                          HapticFeedback.selectionClick();
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
        const SizedBox(height: 14),

        // 4. Connected Device Calendars & Two-Way Sync
        StaggeredReveal(
          index: 3,
          child: GlassContainer(
            padding: const EdgeInsets.all(16),
            borderRadius: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.connectedCalendarsSectionTitle,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
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
                                Icons.event_available_rounded,
                                size: 20,
                                color: SyncroColors.clinicalEmerald,
                              ),
                              title: Text(
                                cal.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${cal.accountName ?? "Local"} • ID: ${cal.id}',
                              ),
                              trailing: Icon(
                                cal.isReadOnly
                                    ? Icons.lock_outline
                                    : Icons.sync_rounded,
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
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () async {
                      HapticFeedback.mediumImpact();
                      final result =
                          await ref.read(calendarSyncServiceProvider).syncAll();
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
                    icon: const Icon(Icons.sync_rounded),
                    label: Text(
                      strings.syncNowButton,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () async {
                      HapticFeedback.mediumImpact();
                      await ref.read(demoSeedServiceProvider).resetAndSeed();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(strings.demoResetSuccess)),
                        );
                      }
                    },
                    icon: const Icon(Icons.restore_rounded),
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

class _ThemeOptionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOptionCard({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return AnimatedScaleTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color:
              isSelected ? primary.withValues(alpha: 0.20) : Colors.transparent,
          border: Border.all(
            color: isSelected
                ? primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? primary : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? primary : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekdayOrb extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _WeekdayOrb({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return AnimatedScaleTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 39,
        height: 39,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    primary,
                    SyncroColors.amethystViolet,
                  ],
                )
              : null,
          border: Border.all(
            color: isSelected
                ? primary
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: isSelected ? Colors.white : null,
          ),
        ),
      ),
    );
  }
}
