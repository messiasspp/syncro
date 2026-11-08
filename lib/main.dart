import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/scheduling/presentation/providers/scheduling_providers.dart';

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

  static const _navDestinations = [
    NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Agenda'),
    NavigationDestination(icon: Icon(Icons.category), label: 'Event Types'),
    NavigationDestination(icon: Icon(Icons.people), label: 'Entities'),
    NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'Scheduler'),
    NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final eventTypesAsync = ref.watch(eventTypesStreamProvider);
    final entitiesAsync = ref.watch(entitiesStreamProvider);
    final appointmentsAsync = ref.watch(appointmentsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Syncro Calendar Engine'),
        actions: [
          IconButton(
            tooltip: 'Sync with Device Calendars',
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
            tooltip: 'Reset & Re-seed Demo Data',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await ref.read(demoSeedServiceProvider).resetAndSeed();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Demo scenarios reset & re-seeded!'),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Active Tab: ${_navDestinations[_selectedIndex].label}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                'Event Types: ${eventTypesAsync.valueOrNull?.length ?? 0} • '
                'Entities: ${entitiesAsync.valueOrNull?.length ?? 0} • '
                'Appointments: ${appointmentsAsync.valueOrNull?.length ?? 0}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
        destinations: _navDestinations,
      ),
    );
  }
}
