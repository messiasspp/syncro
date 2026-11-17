import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/calendar/calendar_client.dart';
import '../../data/calendar/device_calendar_client.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/drift_scheduling_repository.dart';
import '../../data/repositories/scheduling_repository.dart';
import '../../data/seed/demo_seed_service.dart';
import '../../domain/models/appointment.dart';
import '../../domain/models/conflict_report.dart';
import '../../domain/models/entity.dart';
import '../../domain/models/event_type.dart';
import '../../domain/models/external_calendar.dart';
import '../../domain/models/protocol_enrollment.dart';
import '../../domain/models/time_range.dart';
import '../../domain/models/work_schedule.dart';
import '../../domain/services/backup_service.dart';
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

/// Provides real-time detected collisions between Syncro appointments and external calendar events.
final calendarConflictsProvider =
    FutureProvider<Map<String, ConflictReport>>((ref) async {
  ref.watch(appointmentsStreamProvider);
  final syncService = ref.watch(calendarSyncServiceProvider);
  return syncService.detectConflicts();
});

/// Backup, restore & RFC 5545 calendar export service provider.
final backupServiceProvider = Provider<BackupService>((ref) {
  return const BackupService();
});

/// User-selected primary calendar account ID (e.g. primary Google Calendar on device).
final selectedPrimaryCalendarIdProvider = StateProvider<String?>((ref) {
  return null;
});

/// Resolves the active primary Google/local calendar on the device:
/// prefers [selectedPrimaryCalendarIdProvider], then primary `@gmail.com` account,
/// then the first writable non-Syncro calendar.
final activePrimaryCalendarProvider = Provider<ExternalCalendar?>((ref) {
  final calendars = ref.watch(externalCalendarsFutureProvider).valueOrNull ??
      const <ExternalCalendar>[];
  if (calendars.isEmpty) return null;

  final selectedId = ref.watch(selectedPrimaryCalendarIdProvider);
  if (selectedId != null) {
    final match = calendars.where((c) => c.id == selectedId).firstOrNull;
    if (match != null) return match;
  }

  final nonSyncroWritable = calendars
      .where((c) =>
          !c.isReadOnly &&
          !c.name.startsWith('Syncro') &&
          c.accountName != 'Syncro')
      .toList();

  final gmailPrimary = nonSyncroWritable
      .where((c) =>
          c.name.contains('@gmail.com') ||
          (c.accountName?.contains('@gmail.com') ?? false))
      .firstOrNull;

  return gmailPrimary ?? nonSyncroWritable.firstOrNull ?? calendars.first;
});

/// Controls whether external Google/device calendar events are rendered directly in Tab 1 (Agenda).
final showExternalEventsInAgendaProvider = StateProvider<bool>((ref) {
  return true;
});

/// Fetches live external events from connected device calendars (excluding Syncro's own synced copies)
/// so the user can view their real Google Calendar schedule directly inside Syncro's Agenda.
final externalCalendarEventsProvider =
    FutureProvider<List<ExternalCalendarEvent>>((ref) async {
  final showExternal = ref.watch(showExternalEventsInAgendaProvider);
  if (!showExternal) return const [];

  final appointments =
      ref.watch(appointmentsStreamProvider).valueOrNull ?? const <Appointment>[];
  final calendars = await ref.watch(externalCalendarsFutureProvider.future);
  if (calendars.isEmpty) return const [];

  final client = ref.watch(calendarClientProvider);
  final knownSyncroIds = <String>{
    for (final a in appointments)
      if (a.externalCalendarEventId != null) a.externalCalendarEventId!,
  };

  final now = DateTime.now();
  final range = TimeRange(
    start: DateTime(now.year, now.month - 1, 1),
    end: DateTime(now.year, now.month + 4, 28, 23, 59),
  );

  final List<ExternalCalendarEvent> allExternal = [];
  for (final cal in calendars) {
    if (cal.name.startsWith('Syncro') || cal.accountName == 'Syncro') {
      continue;
    }
    final events = await client.retrieveEvents(
      calendarId: cal.id,
      range: range,
    );
    for (final evt in events) {
      if (evt.externalEventId != null &&
          knownSyncroIds.contains(evt.externalEventId)) {
        continue;
      }
      allExternal.add(evt);
    }
  }

  allExternal.sort((a, b) => a.timeRange.compareTo(b.timeRange));
  return allExternal;
});
