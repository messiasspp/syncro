import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncro/features/scheduling/data/calendar/calendar_client.dart';
import 'package:syncro/features/scheduling/data/repositories/scheduling_repository.dart';
import 'package:syncro/features/scheduling/presentation/providers/scheduling_providers.dart';
import 'package:syncro/main.dart';

void main() {
  testWidgets(
      'SyncroApp renders 5-tab UI, seeds demo data, and toggles EN/PT-BR localization in Settings',
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

    // 1. Verify AppBar ('Syncro') & 5 Navigation Destinations in English
    expect(find.text('Syncro'), findsOneWidget);
    expect(find.text('Agenda'), findsWidgets);
    expect(find.text('Event Types'), findsOneWidget);
    expect(find.text('Entities'), findsOneWidget);
    expect(find.text('Scheduler'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // 2. Verify Agenda Tab shows seeded filter chips & summary stats
    expect(find.text('Friends Zone'), findsWidgets);
    expect(find.text('Mounjaro Clinical Study'), findsWidgets);
    expect(find.text('49'), findsWidgets);

    // 3. Navigate to Event Types tab
    await tester.tap(find.text('Event Types'));
    await tester.pumpAndSettle();
    expect(
      find.text('Event Categories & Scheduling Rules'),
      findsOneWidget,
    );

    // 4. Navigate to Entities tab
    await tester.tap(find.text('Entities'));
    await tester.pumpAndSettle();
    expect(
      find.text('Participants, Friends & Patients'),
      findsOneWidget,
    );
    expect(find.text('Mendy'), findsWidgets);

    // 5. Navigate to Scheduler tab
    await tester.tap(find.text('Scheduler'));
    await tester.pumpAndSettle();
    expect(find.text('Smart Slot Finder'), findsOneWidget);
    expect(find.text('Protocol Cascade'), findsOneWidget);

    // 6. Navigate to Settings tab & toggle EN -> PT-BR inside Settings
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Language & Time Format'), findsOneWidget);

    await tester.tap(find.text('Português (Brasil)'));
    await tester.pumpAndSettle();
    expect(find.text('Syncro'), findsOneWidget);
    expect(find.text('Idioma e Formato de Hora'), findsOneWidget);
  });
}
