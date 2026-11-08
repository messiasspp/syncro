import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/app_strings.dart';
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

class SyncroApp extends StatelessWidget {
  const SyncroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Syncro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
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
    AgendaScreen(),
    EventTypesScreen(),
    EntitiesScreen(),
    SchedulerScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final currentLang = ref.watch(appLanguageProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.appTitle),
        actions: [
          Tooltip(
            message: 'Toggle EN / PT-BR',
            child: TextButton.icon(
              icon: const Icon(Icons.translate, size: 18),
              label: Text(
                currentLang == AppLanguage.en ? 'EN' : 'PT',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                ref.read(appLanguageProvider.notifier).state =
                    currentLang == AppLanguage.en
                        ? AppLanguage.ptBr
                        : AppLanguage.en;
              },
            ),
          ),
          IconButton(
            tooltip: strings.syncCalendarsTooltip,
            icon: const Icon(Icons.sync),
            onPressed: () async {
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
            icon: const Icon(Icons.refresh),
            onPressed: () async {
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
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.calendar_month),
            label: strings.tabAgenda,
          ),
          NavigationDestination(
            icon: const Icon(Icons.category),
            label: strings.tabEventTypes,
          ),
          NavigationDestination(
            icon: const Icon(Icons.people),
            label: strings.tabEntities,
          ),
          NavigationDestination(
            icon: const Icon(Icons.auto_awesome),
            label: strings.tabScheduler,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings),
            label: strings.tabSettings,
          ),
        ],
      ),
    );
  }
}
