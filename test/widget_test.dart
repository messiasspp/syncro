import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncro/features/scheduling/data/calendar/calendar_client.dart';
import 'package:syncro/features/scheduling/data/repositories/scheduling_repository.dart';
import 'package:syncro/features/scheduling/presentation/providers/scheduling_providers.dart';
import 'package:syncro/main.dart';

void main() {
  testWidgets('SyncroApp renders 5-tab navigation shell and seeds demo data',
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

    expect(find.text('Syncro Calendar Engine'), findsOneWidget);
    expect(find.text('Agenda'), findsOneWidget);
    expect(find.text('Event Types'), findsOneWidget);
    expect(find.text('Entities'), findsOneWidget);
    expect(find.text('Scheduler'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(
      find.textContaining('Event Types: 2 • Entities: 3 • Appointments: 49'),
      findsOneWidget,
    );
  });
}
