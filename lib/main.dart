import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/app_strings.dart';
import 'core/theme/syncro_theme.dart';
import 'core/widgets/glass_container.dart';
import 'features/scheduling/domain/models/event_type.dart';
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

/// Provides the currently selected bottom navigation tab index.
final selectedTabIndexProvider = StateProvider<int>((ref) => 0);

/// Tracks whether the user has scrolled down in a scrollable list so the
/// Floating Action Button docks/sticks into the Floating Glass Bottom Bar.
final isActionDockedProvider = StateProvider<bool>((ref) => false);

class SyncroHomeScreen extends ConsumerStatefulWidget {
  const SyncroHomeScreen({super.key});

  @override
  ConsumerState<SyncroHomeScreen> createState() => _SyncroHomeScreenState();
}

class _SyncroHomeScreenState extends ConsumerState<SyncroHomeScreen> {
  ScrollPosition? _activeVerticalScrollPosition;

  static const List<Widget> _screens = [
    AgendaScreen(key: ValueKey('tab_agenda')),
    EventTypesScreen(key: ValueKey('tab_event_types')),
    EntitiesScreen(key: ValueKey('tab_entities')),
    SchedulerScreen(key: ValueKey('tab_scheduler')),
    SettingsScreen(key: ValueKey('tab_settings')),
  ];

  void _scrollToTop() {
    HapticFeedback.mediumImpact();
    final pos = _activeVerticalScrollPosition;
    if (pos != null && pos.hasPixels) {
      pos.animateTo(
        0.0,
        duration: const Duration(milliseconds: 460),
        curve: Curves.easeOutCubic,
      );
    }
    ref.read(isActionDockedProvider.notifier).state = false;
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final selectedIndex = ref.watch(selectedTabIndexProvider);
    final isActionDocked = ref.watch(isActionDockedProvider);
    final eventTypes =
        ref.watch(eventTypesStreamProvider).valueOrNull ?? const <EventType>[];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tabLabels = [
      strings.tabAgenda,
      strings.tabEventTypes,
      strings.tabEntities,
      strings.tabScheduler,
      strings.tabSettings,
    ];

    final (String? actionLabel, IconData actionIcon, VoidCallback? onActionTap) =
        switch (selectedIndex) {
      0 => (
          strings.quickScheduleButton,
          Icons.add_rounded,
          () {
            ref.read(isActionDockedProvider.notifier).state = false;
            ref.read(selectedTabIndexProvider.notifier).state = 3;
          }
        ),
      1 => (
          strings.newEventTypeButton,
          Icons.add_rounded,
          () => EventTypesScreen.showCreateEventTypeDialog(
                context,
                ref,
                strings,
              )
        ),
      2 => (
          strings.newEntityButton,
          Icons.person_add_alt_1_rounded,
          () => EntitiesScreen.showCreateEntityDialog(
                context,
                ref,
                strings,
                eventTypes,
              )
        ),
      _ => (null, Icons.add_rounded, null),
    };

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
            Text(
              strings.appTitle,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.32),
                ),
              ),
              child: Text(
                tabLabels[selectedIndex],
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AnimatedScaleTap(
              onTap: () async {
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
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: SyncroColors.clinicalEmerald.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: SyncroColors.clinicalEmerald.withValues(alpha: 0.40),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_done_rounded,
                      size: 15,
                      color: SyncroColors.clinicalEmerald,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      strings.syncedBadge,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: SyncroColors.clinicalEmerald,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical) {
            final ctx = notification.context;
            if (ctx is StatefulElement && ctx.state is ScrollableState) {
              _activeVerticalScrollPosition =
                  (ctx.state as ScrollableState).position;
            } else if (ctx != null) {
              _activeVerticalScrollPosition = Scrollable.maybeOf(ctx)?.position;
            }

            final hasScrollSpace = notification.metrics.maxScrollExtent > 20;
            final shouldDock =
                hasScrollSpace && notification.metrics.pixels > 28;
            if (shouldDock != isActionDocked) {
              ref.read(isActionDockedProvider.notifier).state = shouldDock;
            }
          }
          return false;
        },
        child: AmbientMeshBackground(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _screens[selectedIndex],
          ),
        ),
      ),
      bottomNavigationBar: FloatingGlassNavBar(
        selectedIndex: selectedIndex,
        isActionDocked: isActionDocked,
        actionLabel: actionLabel,
        actionIcon: actionIcon,
        onActionTap: onActionTap,
        onScrollToTopTap: _scrollToTop,
        onDestinationSelected: (idx) {
          ref.read(isActionDockedProvider.notifier).state = false;
          ref.read(selectedTabIndexProvider.notifier).state = idx;
        },
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
