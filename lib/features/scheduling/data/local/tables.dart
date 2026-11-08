import 'dart:convert';
import 'package:drift/drift.dart';
import '../../domain/models/event_type.dart';

/// Converts a `Set<int>` of workdays (e.g., `{1, 2, 3, 4, 5}`) to and from
/// a JSON array string (e.g., `"[1,2,3,4,5]"`) for SQLite storage.
class WorkDaysSetConverter extends TypeConverter<Set<int>, String> {
  const WorkDaysSetConverter();

  @override
  Set<int> fromSql(String fromDb) => decode(fromDb);

  @override
  String toSql(Set<int> value) => encode(value);

  static Set<int> decode(String rawJson) {
    if (rawJson.trim().isEmpty) return const {};
    final List<dynamic> decoded = jsonDecode(rawJson) as List<dynamic>;
    return decoded.map((e) => e as int).toSet();
  }

  static String encode(Set<int> days) {
    final sorted = days.toList()..sort();
    return jsonEncode(sorted);
  }
}

/// Converts a `List<DayTimeWindow>` (allowed windows or entity availability overrides)
/// to and from a JSON string for SQLite storage.
class DayTimeWindowListConverter
    extends TypeConverter<List<DayTimeWindow>, String> {
  const DayTimeWindowListConverter();

  @override
  List<DayTimeWindow> fromSql(String fromDb) => decode(fromDb);

  @override
  String toSql(List<DayTimeWindow> value) => encode(value);

  static List<DayTimeWindow> decode(String rawJson) {
    if (rawJson.trim().isEmpty) return const [];
    final List<dynamic> list = jsonDecode(rawJson) as List<dynamic>;
    return list
        .map((item) => DayTimeWindow.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static String encode(List<DayTimeWindow> windows) {
    return jsonEncode(windows.map((w) => w.toJson()).toList());
  }
}

/// Table storing the user's primary work schedule configuration.
/// Uses a singleton row (`id = 'default'`) by convention.
class WorkSchedulesTable extends Table {
  @override
  String get tableName => 'work_schedules';

  TextColumn get id => text().withDefault(const Constant('default'))();
  TextColumn get workDaysJson =>
      text().map(const WorkDaysSetConverter()).withDefault(const Constant('[1,2,3,4,5]'))();
  IntColumn get startHour => integer().withDefault(const Constant(8))();
  IntColumn get startMinute => integer().withDefault(const Constant(0))();
  IntColumn get endHour => integer().withDefault(const Constant(18))();
  IntColumn get endMinute => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Table storing Event Type categories and their scheduling rules
/// (e.g., "Friends Zone", "Mounjaro Clinical Study").
class EventTypesTable extends Table {
  @override
  String get tableName => 'event_types';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get colorHex => text().withDefault(const Constant('#2196F3'))();
  TextColumn get workHoursConstraint =>
      text().withDefault(const Constant('bothFlexible'))();
  IntColumn get minDurationMinutes => integer()();
  IntColumn get maxDurationMinutes => integer()();
  IntColumn get bufferBeforeMinutes => integer().withDefault(const Constant(0))();
  IntColumn get bufferAfterMinutes => integer().withDefault(const Constant(0))();
  TextColumn get schedulingMode =>
      text().withDefault(const Constant('suggestTopRanked'))();
  TextColumn get allowedTimeWindowsJson =>
      text().map(const DayTimeWindowListConverter()).withDefault(const Constant('[]'))();
  TextColumn get calendarMappingId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Table storing scheduling participants (friends, contacts, or clinical trial patients).
class EntitiesTable extends Table {
  @override
  String get tableName => 'entities';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get defaultEventTypeId =>
      text().nullable().references(EventTypesTable, #id)();
  TextColumn get customAvailabilityOverridesJson =>
      text().map(const DayTimeWindowListConverter()).withDefault(const Constant('[]'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Table storing structured multi-visit protocol enrollments
/// (e.g., a 1-year, 24-visit clinical study with a 14-day cadence).
class ProtocolEnrollmentsTable extends Table {
  @override
  String get tableName => 'protocol_enrollments';

  TextColumn get id => text()();
  TextColumn get entityId => text().references(EntitiesTable, #id)();
  TextColumn get eventTypeId => text().references(EventTypesTable, #id)();
  TextColumn get protocolName => text()();
  IntColumn get startDateEpochMs => integer()();
  IntColumn get totalVisits => integer().withDefault(const Constant(24))();
  IntColumn get cadenceDays => integer().withDefault(const Constant(14))();
  IntColumn get toleranceWindowDays => integer().withDefault(const Constant(3))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Table storing scheduled or suggested calendar appointments.
class AppointmentsTable extends Table {
  @override
  String get tableName => 'appointments';

  TextColumn get id => text()();
  TextColumn get entityId => text().references(EntitiesTable, #id)();
  TextColumn get eventTypeId => text().references(EventTypesTable, #id)();
  IntColumn get startEpochMs => integer()();
  IntColumn get endEpochMs => integer()();
  TextColumn get status => text().withDefault(const Constant('suggested'))();
  IntColumn get visitIndex => integer().nullable()();
  TextColumn get protocolEnrollmentId =>
      text().nullable().references(ProtocolEnrollmentsTable, #id)();
  TextColumn get externalCalendarEventId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
