import '../../domain/models/external_calendar.dart';
import '../../domain/models/time_range.dart';

/// Platform-agnostic contract for interacting with device or cloud calendars.
///
/// Decouples Syncro's scheduling engine from platform channel specifics
/// (iOS EventKit, Android CalendarProvider, or Desktop REST APIs).
abstract class CalendarClient {
  /// Requests read/write calendar permissions from the operating system.
  Future<bool> requestPermissions();

  /// Checks whether calendar permissions have already been granted.
  Future<bool> hasPermissions();

  /// Returns all accessible calendars on the device/account.
  Future<List<ExternalCalendar>> retrieveCalendars();

  /// Creates a new dedicated sub-calendar (e.g. "Syncro — Mounjaro Clinical Study")
  /// and returns its newly assigned calendar ID.
  Future<String> createDedicatedCalendar({
    required String name,
    required String colorHex,
  });

  /// Retrieves all events within [range] for the given [calendarId].
  Future<List<ExternalCalendarEvent>> retrieveEvents({
    required String calendarId,
    required TimeRange range,
  });

  /// Creates a new calendar event (when `event.externalEventId == null`) or updates
  /// an existing event on the target calendar, returning its `externalEventId`.
  Future<String> createOrUpdateEvent(ExternalCalendarEvent event);

  /// Deletes an event from the specified calendar.
  Future<bool> deleteEvent({
    required String calendarId,
    required String externalEventId,
  });
}

/// Pure-Dart in-memory implementation of [CalendarClient] for unit tests,
/// desktop sandboxes, and offline simulation.
class InMemoryCalendarClient implements CalendarClient {
  bool _permissionsGranted;
  int _calendarIdCounter = 1;
  int _eventIdCounter = 1000;

  final Map<String, ExternalCalendar> _calendars = {};
  final Map<String, Map<String, ExternalCalendarEvent>> _eventsByCalendar = {};

  InMemoryCalendarClient({
    bool permissionsGranted = true,
    List<ExternalCalendar>? initialCalendars,
  }) : _permissionsGranted = permissionsGranted {
    final seedCalendars = initialCalendars ??
        const [
          ExternalCalendar(
            id: 'cal_personal_primary',
            name: 'Personal (Google Calendar)',
            accountName: 'user@gmail.com',
            colorHex: '#4285F4',
          ),
          ExternalCalendar(
            id: 'cal_work_primary',
            name: 'Clinical Work (Apple Calendar)',
            accountName: 'iCloud',
            colorHex: '#34A853',
          ),
        ];

    for (final cal in seedCalendars) {
      _calendars[cal.id] = cal;
      _eventsByCalendar[cal.id] = {};
    }
  }

  void setPermissionsGranted(bool granted) {
    _permissionsGranted = granted;
  }

  @override
  Future<bool> requestPermissions() async {
    _permissionsGranted = true;
    return true;
  }

  @override
  Future<bool> hasPermissions() async => _permissionsGranted;

  @override
  Future<List<ExternalCalendar>> retrieveCalendars() async {
    if (!_permissionsGranted) return const [];
    return _calendars.values.toList();
  }

  @override
  Future<String> createDedicatedCalendar({
    required String name,
    required String colorHex,
  }) async {
    if (!_permissionsGranted) {
      throw StateError('Calendar permissions have not been granted.');
    }

    // Reuse if a calendar with the exact name already exists
    for (final existing in _calendars.values) {
      if (existing.name == name) {
        return existing.id;
      }
    }

    final id = 'syncro_subcal_${_calendarIdCounter++}';
    final calendar = ExternalCalendar(
      id: id,
      name: name,
      accountName: 'Syncro Local',
      colorHex: colorHex,
      isReadOnly: false,
    );
    _calendars[id] = calendar;
    _eventsByCalendar[id] = {};
    return id;
  }

  @override
  Future<List<ExternalCalendarEvent>> retrieveEvents({
    required String calendarId,
    required TimeRange range,
  }) async {
    if (!_permissionsGranted) return const [];
    final calendarEvents = _eventsByCalendar[calendarId];
    if (calendarEvents == null) return const [];

    return calendarEvents.values
        .where((e) => e.timeRange.overlaps(range))
        .toList()
      ..sort((a, b) => a.timeRange.compareTo(b.timeRange));
  }

  @override
  Future<String> createOrUpdateEvent(ExternalCalendarEvent event) async {
    if (!_permissionsGranted) {
      throw StateError('Calendar permissions have not been granted.');
    }

    final calendarEvents = _eventsByCalendar.putIfAbsent(
      event.calendarId,
      () => {},
    );

    final assignedId =
        event.externalEventId ?? 'ext_evt_${_eventIdCounter++}';
    final storedEvent = event.copyWith(externalEventId: assignedId);
    calendarEvents[assignedId] = storedEvent;
    return assignedId;
  }

  @override
  Future<bool> deleteEvent({
    required String calendarId,
    required String externalEventId,
  }) async {
    final calendarEvents = _eventsByCalendar[calendarId];
    if (calendarEvents == null) return false;
    return calendarEvents.remove(externalEventId) != null;
  }
}
