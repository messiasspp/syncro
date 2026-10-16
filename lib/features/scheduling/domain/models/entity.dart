import 'event_type.dart';

/// Represents a scheduling participant: a contact, friend, or clinical patient.
class Entity {
  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? defaultEventTypeId;

  /// Custom availability windows specific to this person.
  /// When present, this overrides or restricts the default EventType windows.
  /// (e.g. "Patient 102 can only come Wednesdays after 10:00").
  final List<DayTimeWindow> customAvailabilityOverrides;

  const Entity({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.defaultEventTypeId,
    this.customAvailabilityOverrides = const [],
  });
}
