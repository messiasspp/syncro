import 'package:flutter/material.dart';

void main() {
  runApp(const SyncroApp());
}

class SyncroApp extends StatelessWidget {
  const SyncroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Syncro',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const SyncroHomeScreen(),
    );
  }
}

class SyncroHomeScreen extends StatefulWidget {
  const SyncroHomeScreen({super.key});

  @override
  State<SyncroHomeScreen> createState() => _SyncroHomeScreenState();
}

class _SyncroHomeScreenState extends State<SyncroHomeScreen> {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Syncro Calendar Engine'),
      ),
      body: Center(
        child: Text(
          'Active Tab: ${_navDestinations[_selectedIndex].label}',
          style: Theme.of(context).textTheme.headlineSmall,
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
