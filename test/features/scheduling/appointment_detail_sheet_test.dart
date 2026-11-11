import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncro/core/l10n/app_strings.dart';
import 'package:syncro/features/scheduling/data/calendar/calendar_client.dart';
import 'package:syncro/features/scheduling/data/repositories/scheduling_repository.dart';
import 'package:syncro/features/scheduling/domain/models/appointment.dart';
import 'package:syncro/features/scheduling/domain/models/entity.dart';
import 'package:syncro/features/scheduling/domain/models/event_type.dart';
import 'package:syncro/features/scheduling/domain/models/time_range.dart';
import 'package:syncro/features/scheduling/presentation/providers/scheduling_providers.dart';
import 'package:syncro/features/scheduling/presentation/widgets/appointment_detail_sheet.dart';

void main() {
  testWidgets(
      'AppointmentDetailSheet renders details, updates status, and saves rescheduled time',
      (WidgetTester tester) async {
    final repo = InMemorySchedulingRepository();
    final client = InMemoryCalendarClient();

    final testApt = Appointment(
      id: 'apt_test_1',
      entityId: 'entity_test',
      eventTypeId: 'type_test',
      timeRange: TimeRange(
        start: DateTime(2026, 10, 20, 10, 0),
        end: DateTime(2026, 10, 20, 10, 45),
      ),
      status: AppointmentStatus.suggested,
    );

    const testEntity = Entity(
      id: 'entity_test',
      name: 'Dr. Jane Smith',
      defaultEventTypeId: 'type_test',
    );

    const testEventType = EventType(
      id: 'type_test',
      name: 'Cardiology Review',
      colorHex: '#14B8A6',
      minDuration: Duration(minutes: 45),
      maxDuration: Duration(minutes: 60),
    );

    await repo.upsertAppointment(testApt);
    await repo.upsertEntity(testEntity);
    await repo.upsertEventType(testEventType);

    const strings = AppStrings(language: AppLanguage.en);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          schedulingRepositoryProvider.overrideWithValue(repo),
          calendarClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => AppointmentDetailSheet.show(
                    ctx,
                    appointment: testApt,
                    entity: testEntity,
                    eventType: testEventType,
                    strings: strings,
                  ),
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Open the Sheet
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // 2. Verify participant, category, status chips, and date/time
    expect(find.text('Dr. Jane Smith'), findsOneWidget);
    expect(find.text('Cardiology Review'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Suggested'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);

    // 3. Switch status to 'Confirmed'
    await tester.tap(find.text('Confirmed'));
    await tester.pumpAndSettle();

    // 4. Change duration to 60 min
    await tester.tap(find.text('60 min'));
    await tester.pumpAndSettle();

    // 5. Scroll to and tap 'Save Changes'
    await tester.scrollUntilVisible(
      find.text('Save Changes'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    // 6. Verify persistence in repository
    final all = await repo.getAllAppointments();
    final saved = all.where((a) => a.id == 'apt_test_1').firstOrNull;
    expect(saved, isNotNull);
    expect(saved!.status, AppointmentStatus.confirmed);
    expect(saved.timeRange.duration.inMinutes, 60);
  });
}
