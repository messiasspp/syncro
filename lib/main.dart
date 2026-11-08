import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/app_strings.dart';
import 'core/theme/syncro_theme.dart';
import 'core/widgets/glass_container.dart';
import 'features/scheduling/presentation/providers/scheduling_providers.dart';
import 'features/scheduling/presentation/screens/agenda_screen.dart';
import 'features/scheduling/presentation/screens/entities_screen.dart';
import 'features/scheduling/presentation/screens/event_types_screen.dart';
import 'features/scheduling/presentation/screens/scheduler_screen.dart';
import 'features/scheduling/presentation/screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: SyncroApp(),
    ),
  );
}

class SyncroApp extends ConsumerWidget {
  const SyncroApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Syncro',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: SyncroTheme.lightTheme,
      darkTheme: SyncroTheme.darkTheme,
      home: const SyncroHomeScreen(),
    );
  }
}

class SyncroHomeScreen extends ConsumerStatefulWidget {
  const SyncroHomeScreen({super.key});

  @override
  ConsumerState<SyncroHomeScreen> createState() => _SyncroHomeScreenState();
}

class _SyncroHomeScreenState extends ConsumerState<SyncroHomeScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = [
    AgendaScreen(key: ValueKey('tab_agenda')),
    EventTypesScreen(key: ValueKey('tab_event_types')),
    EntitiesScreen(key: ValueKey('tab_entities')),
    SchedulerScreen(key: ValueKey('tab_scheduler')),
    SettingsScreen(key: ValueKey('tab_settings')),
  ];

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final currentLang = ref.watch(appLanguageProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: (isDark
                        ? SyncroColors.darkCanvas
                        : SyncroColors.lightCanvas)
                    .withValues(alpha: 0.72),
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : SyncroColors.electricIndigo.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SyncroColors.clinicalEmerald,
                boxShadow: [
                  BoxShadow(
                    color: SyncroColors.clinicalEmerald.withValues(alpha: 0.7),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                strings.appTitle,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Toggle Dark / Light Mode',
            icon: Icon(
              themeMode == ThemeMode.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              size: 20,
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              ref.read(themeModeProvider.notifier).state =
                  themeMode == ThemeMode.dark
                      ? ThemeMode.light
                      : ThemeMode.dark;
            },
          ),
          Tooltip(
            message: 'Toggle EN / PT-BR',
            child: TextButton.icon(
              icon: const Icon(Icons.translate_rounded, size: 17),
              label: Text(
                currentLang == AppLanguage.en ? 'EN' : 'PT',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              onPressed: () {
                HapticFeedback.selectionClick();
                ref.read(appLanguageProvider.notifier).state =
                    currentLang == AppLanguage.en
                        ? AppLanguage.ptBr
                        : AppLanguage.en;
              },
            ),
          ),
          IconButton(
            tooltip: strings.syncCalendarsTooltip,
            icon: const Icon(Icons.sync_rounded),
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
          ),
          IconButton(
            tooltip: strings.resetDemoDataTooltip,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () async {
              HapticFeedback.mediumImpact();
              await ref.read(demoSeedServiceProvider).resetAndSeed();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(strings.demoResetSuccess),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: AmbientMeshBackground(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _screens[_selectedIndex],
        ),
      ),
      bottomNavigationBar: FloatingGlassNavBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
        destinations: [
          GlassNavDestination(
            icon: Icons.calendar_month_outlined,
            activeIcon: Icons.calendar_month_rounded,
            label: strings.tabAgenda,
          ),
          GlassNavDestination(
            icon: Icons.category_outlined,
            activeIcon: Icons.category_rounded,
            label: strings.tabEventTypes,
          ),
          GlassNavDestination(
            icon: Icons.people_outline_rounded,
            activeIcon: Icons.people_rounded,
            label: strings.tabEntities,
          ),
          GlassNavDestination(
            icon: Icons.auto_awesome_outlined,
            activeIcon: Icons.auto_awesome_rounded,
            label: strings.tabScheduler,
          ),
          GlassNavDestination(
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings_rounded,
            label: strings.tabSettings,
          ),
        ],
      ),
    );
  }
}
