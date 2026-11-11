import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncro/features/scheduling/data/calendar/calendar_client.dart';
import 'package:syncro/features/scheduling/data/repositories/scheduling_repository.dart';
import 'package:syncro/features/scheduling/presentation/providers/scheduling_providers.dart';
import 'package:syncro/main.dart';

void main() {
  testWidgets(
      'AgendaScreen switches between Timeline, Month Grid, and Week Matrix views seamlessly',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          schedulingRepositoryProvider
              .overrideWithValue(InMemorySchedulingRepository()),
          calendarClientProvider.overrideWithValue(InMemoryCalendarClient()),
        ],
        child: const SyncroApp(),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Initial Timeline View
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);

    // 2. Switch to Month View
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();

    // Month view header & Today button
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left_rounded), findsWidgets);
    expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);

    // 3. Switch to Week View
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();

    // Week view range header
    expect(find.textContaining('2026'), findsWidgets);

    // 4. Switch back to Timeline View
    await tester.tap(find.text('Timeline'));
    await tester.pumpAndSettle();
    expect(find.text('Friends Zone'), findsWidgets);
  });
}
