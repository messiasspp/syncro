import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/calendar/calendar_client.dart';
import '../../data/calendar/device_calendar_client.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/drift_scheduling_repository.dart';
import '../../data/repositories/scheduling_repository.dart';
import '../../data/seed/demo_seed_service.dart';
import '../../domain/models/appointment.dart';
import '../../domain/models/entity.dart';
import '../../domain/models/event_type.dart';
import '../../domain/models/external_calendar.dart';
import '../../domain/models/protocol_enrollment.dart';
import '../../domain/models/work_schedule.dart';
import '../../domain/services/calendar_sync_service.dart';

/// Singleton Drift SQLite database provider.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() {
    db.close();
  });
  return db;
});

/// Core repository provider. Can be overridden in tests with [InMemorySchedulingRepository].
final schedulingRepositoryProvider = Provider<SchedulingRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return DriftSchedulingRepository(db);
});

/// Platform-aware CalendarClient provider (`device_calendar` on iOS/Android,
/// with transparent in-memory sandbox fallback on desktop/tests).
final calendarClientProvider = Provider<CalendarClient>((ref) {
  return NativeDeviceCalendarClient();
});

/// Two-way Calendar Synchronization & Busy-Slot Aggregation Service provider.
final calendarSyncServiceProvider = Provider<CalendarSyncService>((ref) {
  final repository = ref.watch(schedulingRepositoryProvider);
  final calendarClient = ref.watch(calendarClientProvider);
  return CalendarSyncService(
    repository: repository,
    calendarClient: calendarClient,
  );
});

/// Provides the list of accessible native/external calendars on the device.
final externalCalendarsFutureProvider =
    FutureProvider<List<ExternalCalendar>>((ref) async {
  final client = ref.watch(calendarClientProvider);
  final granted = await client.requestPermissions();
  if (!granted) return const [];
  return client.retrieveCalendars();
});

/// Demo scenario seeder service provider.
final demoSeedServiceProvider = Provider<DemoSeedService>((ref) {
  final repository = ref.watch(schedulingRepositoryProvider);
  return DemoSeedService(repository);
});

/// Runs once at startup to seed the "Friends Zone" and "Mounjaro Study" scenarios if the DB is empty.
final databaseInitializerProvider = FutureProvider<bool>((ref) async {
  final seeder = ref.watch(demoSeedServiceProvider);
  return seeder.seedIfEmpty();
});

/// Reactive stream of the user's configured [WorkSchedule].
final workScheduleStreamProvider = StreamProvider<WorkSchedule>((ref) async* {
  await ref.watch(databaseInitializerProvider.future);
  final repo = ref.watch(schedulingRepositoryProvider);
  yield* repo.watchWorkSchedule();
});

/// Reactive stream of all configured [EventType] categories.
final eventTypesStreamProvider = StreamProvider<List<EventType>>((ref) async* {
  await ref.watch(databaseInitializerProvider.future);
  final repo = ref.watch(schedulingRepositoryProvider);
  yield* repo.watchAllEventTypes();
});

/// Reactive stream of all participants ([Entity]: Friends & Clinical Patients).
final entitiesStreamProvider = StreamProvider<List<Entity>>((ref) async* {
  await ref.watch(databaseInitializerProvider.future);
  final repo = ref.watch(schedulingRepositoryProvider);
  yield* repo.watchAllEntities();
});

/// Reactive stream of all [ProtocolEnrollment] roadmaps.
final protocolEnrollmentsStreamProvider =
    StreamProvider<List<ProtocolEnrollment>>((ref) async* {
  await ref.watch(databaseInitializerProvider.future);
  final repo = ref.watch(schedulingRepositoryProvider);
  yield* repo.watchAllProtocolEnrollments();
});

/// Reactive stream of all scheduled and suggested [Appointment] items.
final appointmentsStreamProvider =
    StreamProvider<List<Appointment>>((ref) async* {
  await ref.watch(databaseInitializerProvider.future);
  final repo = ref.watch(schedulingRepositoryProvider);
  yield* repo.watchAllAppointments();
});
