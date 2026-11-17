import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/syncro_theme.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../domain/models/work_schedule.dart';
import '../../domain/services/backup_service.dart';
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
        const SizedBox(height: 14),

        // 5. Data Management, Full Backup & Standard ICS Export
        StaggeredReveal(
          index: 4,
          child: GlassContainer(
            padding: const EdgeInsets.all(16),
            borderRadius: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.backup_table_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.dataManagementSectionTitle,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Export JSON Card
                _DataActionTile(
                  icon: Icons.data_object_rounded,
                  title: strings.exportJsonLabel,
                  subtitle: strings.exportJsonSubtitle,
                  buttonLabel: strings.copyJsonAction,
                  accentColor: Theme.of(context).colorScheme.primary,
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    final repo = ref.read(schedulingRepositoryProvider);
                    final backupService = ref.read(backupServiceProvider);
                    final json = await backupService.exportBackupJson(repo);
                    if (context.mounted) {
                      _showExportDialog(
                        context,
                        title: strings.exportJsonLabel,
                        content: json,
                        filename:
                            'syncro_backup_${DateTime.now().millisecondsSinceEpoch}.json',
                        strings: strings,
                        backupService: backupService,
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
                // Export ICS Card
                _DataActionTile(
                  icon: Icons.calendar_month_rounded,
                  title: strings.exportIcsLabel,
                  subtitle: strings.exportIcsSubtitle,
                  buttonLabel: strings.copyIcsAction,
                  accentColor: SyncroColors.clinicalEmerald,
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    final repo = ref.read(schedulingRepositoryProvider);
                    final backupService = ref.read(backupServiceProvider);
                    final ics = await backupService.exportIcs(repo);
                    if (context.mounted) {
                      _showExportDialog(
                        context,
                        title: strings.exportIcsLabel,
                        content: ics,
                        filename:
                            'syncro_calendar_${DateTime.now().millisecondsSinceEpoch}.ics',
                        strings: strings,
                        backupService: backupService,
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
                // Restore JSON Card
                _DataActionTile(
                  icon: Icons.restore_page_rounded,
                  title: strings.importJsonLabel,
                  subtitle: strings.importJsonSubtitle,
                  buttonLabel: strings.pasteAndImportAction,
                  accentColor: SyncroColors.amberSuggested,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    _showImportDialog(context, ref, strings: strings);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 6. Dynamic Message Template Customizer (WhatsApp / SMS / Email)
        StaggeredReveal(
          index: 5,
          child: GlassContainer(
            padding: const EdgeInsets.all(16),
            borderRadius: 20,
            child: Builder(
              builder: (context) {
                final activeTone = ref.watch(activeMessageToneProvider);
                final customTemplate = ref.watch(customMessageTemplateProvider);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            strings.isPt
                                ? 'Templates de Mensagem (WhatsApp / SMS)'
                                : 'Dynamic Message Templates (WhatsApp / SMS)',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final (tone, label) in [
                          (
                            MessageTone.friendly,
                            strings.isPt ? 'Casual' : 'Friendly',
                          ),
                          (
                            MessageTone.clinical,
                            strings.isPt ? 'Clínico' : 'Clinical',
                          ),
                          (
                            MessageTone.reminder,
                            strings.isPt ? 'Lembrete' : 'Reminder',
                          ),
                          (
                            MessageTone.custom,
                            strings.isPt ? 'Personalizado' : 'Custom',
                          ),
                        ])
                          ChoiceChip(
                            label: Text(label),
                            selected: activeTone == tone,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) {
                              HapticFeedback.selectionClick();
                              ref
                                  .read(activeMessageToneProvider.notifier)
                                  .state = tone;
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _DataActionTile(
                      icon: Icons.edit_note_rounded,
                      title: strings.isPt
                          ? 'Editor de Template com Variáveis'
                          : 'Variable Template Editor',
                      subtitle: customTemplate != null &&
                              customTemplate.trim().isNotEmpty
                          ? customTemplate
                          : '{name}, {category}, {date}, {time}, {visit}',
                      buttonLabel: strings.isPt ? 'Editar' : 'Edit',
                      accentColor: SyncroColors.amethystViolet,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showCustomTemplateDialog(
                          context,
                          ref,
                          strings: strings,
                        );
                      },
                    ),
                  ],
                );
              },
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

class _DataActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final Color accentColor;
  final VoidCallback onTap;

  const _DataActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withValues(alpha: 0.16),
            ),
            child: Icon(icon, size: 20, color: accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: accentColor.withValues(alpha: 0.20),
              foregroundColor: accentColor,
            ),
            onPressed: onTap,
            child: Text(
              buttonLabel,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showExportDialog(
  BuildContext context, {
  required String title,
  required String content,
  required String filename,
  required AppStrings strings,
  required BackupService backupService,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: isDark ? SyncroColors.darkSurface : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.output_rounded,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${content.length} characters • $filename',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Container(
              height: 180,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black26
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: Text(strings.cancelAction),
        ),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: Text(strings.copiedToClipboard.split('!').first),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: content));
            if (context.mounted) {
              Navigator.of(dialogCtx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(strings.copiedToClipboard)),
              );
            }
          },
        ),
        FilledButton.icon(
          icon: const Icon(Icons.save_alt_rounded, size: 16),
          label: const Text('Save File'),
          onPressed: () async {
            try {
              final file =
                  await backupService.saveExportToFile(content, filename);
              if (context.mounted) {
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Saved to ${file.path}')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Save error: $e')),
                );
              }
            }
          },
        ),
      ],
    ),
  );
}

Future<void> _showImportDialog(
  BuildContext context,
  WidgetRef ref, {
  required AppStrings strings,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final textController = TextEditingController();

  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: isDark ? SyncroColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.restore_page_rounded,
                color: SyncroColors.amberSuggested),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                strings.importBackupDialogTitle,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.importConfirmWarning,
                style: const TextStyle(
                  fontSize: 12,
                  color: SyncroColors.amberSuggested,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                maxLines: 6,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                decoration: InputDecoration(
                  hintText: '{\n  "version": 1,\n  "workSchedule": ...\n}',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  suffixIcon: IconButton(
                    tooltip: 'Paste from Clipboard',
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: () async {
                      final data =
                          await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null) {
                        setState(() {
                          textController.text = data!.text!;
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(strings.cancelAction),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SyncroColors.coralAlert,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final raw = textController.text.trim();
              if (raw.isEmpty) return;
              try {
                final repo = ref.read(schedulingRepositoryProvider);
                final backupService = ref.read(backupServiceProvider);
                final summary = await backupService.importBackupJson(repo, raw);

                ref.invalidate(workScheduleStreamProvider);
                ref.invalidate(eventTypesStreamProvider);
                ref.invalidate(entitiesStreamProvider);
                ref.invalidate(protocolEnrollmentsStreamProvider);
                ref.invalidate(appointmentsStreamProvider);
                ref.invalidate(calendarConflictsProvider);

                if (context.mounted) {
                  Navigator.of(dialogCtx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${strings.importSuccessBanner} (${summary.eventTypesCount} types, ${summary.entitiesCount} entities, ${summary.appointmentsCount} apts)',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${strings.importErrorBanner} $e'),
                      backgroundColor: SyncroColors.coralAlert,
                    ),
                  );
                }
              }
            },
            child: Text(strings.importJsonLabel),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showCustomTemplateDialog(
  BuildContext context,
  WidgetRef ref, {
  required AppStrings strings,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final current = ref.read(customMessageTemplateProvider) ??
      strings.defaultCustomTemplate();
  final controller = TextEditingController(text: current);

  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: isDark ? SyncroColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(
              Icons.edit_note_rounded,
              color: SyncroColors.amethystViolet,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                strings.isPt
                    ? 'Template Personalizado'
                    : 'Custom Message Template',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.isPt
                    ? 'Toque em uma variável abaixo para inserir no texto:'
                    : 'Tap any placeholder chip below to insert it:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in const [
                    '{name}',
                    '{category}',
                    '{date}',
                    '{time}',
                    '{visit}',
                  ])
                    ActionChip(
                      label: Text(
                        tag,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() {
                          controller.text = '${controller.text} $tag';
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 4,
                decoration: InputDecoration(
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
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(strings.cancelAction),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              ref.read(customMessageTemplateProvider.notifier).state =
                  text.isEmpty ? null : text;
              ref.read(activeMessageToneProvider.notifier).state =
                  MessageTone.custom;
              Navigator.of(dialogCtx).pop();
            },
            child: Text(strings.isPt ? 'Salvar Template' : 'Save Template'),
          ),
        ],
      ),
    ),
  );
}
