import 'dart:io';

import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../domain/models/external_calendar.dart';
import '../../domain/models/time_range.dart';
import 'calendar_client.dart';

/// Production [CalendarClient] backed by `package:device_calendar`
/// (iOS EventKit & Android CalendarProvider).
///
/// On desktop platforms (Windows, Linux, macOS) where `device_calendar`
/// native channels are unavailable, this adapter transparently delegates
/// to an internal [InMemoryCalendarClient] sandbox so the app remains fully
/// functional across all targets.
class NativeDeviceCalendarClient implements CalendarClient {
  final DeviceCalendarPlugin _plugin;
  final InMemoryCalendarClient _fallbackClient;

  NativeDeviceCalendarClient({
    DeviceCalendarPlugin? plugin,
    InMemoryCalendarClient? fallbackClient,
  })  : _plugin = plugin ?? DeviceCalendarPlugin(),
        _fallbackClient = fallbackClient ?? InMemoryCalendarClient();

  bool get _supportsNativeDeviceCalendar {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  Future<bool> requestPermissions() async {
    if (!_supportsNativeDeviceCalendar) {
      return _fallbackClient.requestPermissions();
    }

    try {
      final status = await _plugin.hasPermissions();
      if (status.isSuccess && (status.data ?? false)) {
        return true;
      }
      final requested = await _plugin.requestPermissions();
      return requested.isSuccess && (requested.data ?? false);
    } on MissingPluginException {
      return _fallbackClient.requestPermissions();
    }
  }

  @override
  Future<bool> hasPermissions() async {
    if (!_supportsNativeDeviceCalendar) {
      return _fallbackClient.hasPermissions();
    }

    try {
      final status = await _plugin.hasPermissions();
      return status.isSuccess && (status.data ?? false);
    } on MissingPluginException {
      return _fallbackClient.hasPermissions();
    }
  }

  @override
  Future<List<ExternalCalendar>> retrieveCalendars() async {
    if (!_supportsNativeDeviceCalendar) {
      return _fallbackClient.retrieveCalendars();
    }

    try {
      final result = await _plugin.retrieveCalendars();
      final calendars = result.data ?? const <Calendar>[];
      return calendars
          .where((c) => c.id != null)
          .map(
            (c) => ExternalCalendar(
              id: c.id!,
              name: c.name ?? 'Unnamed Calendar',
              accountName: c.accountName,
              colorHex: _intColorToHex(c.color),
              isReadOnly: c.isReadOnly ?? false,
            ),
          )
          .toList();
    } on MissingPluginException {
      return _fallbackClient.retrieveCalendars();
    }
  }

  @override
  Future<String> createDedicatedCalendar({
    required String name,
    required String colorHex,
  }) async {
    if (!_supportsNativeDeviceCalendar) {
      return _fallbackClient.createDedicatedCalendar(
        name: name,
        colorHex: colorHex,
      );
    }

    try {
      final existing = await retrieveCalendars();
      for (final cal in existing) {
        if (cal.name == name && !cal.isReadOnly) {
          return cal.id;
        }
      }

      final result = await _plugin.createCalendar(
        name,
        calendarColor: _hexToColor(colorHex),
        localAccountName: 'Syncro',
      );

      if (!result.isSuccess || result.data == null) {
        throw StateError('Failed to create native device calendar "$name".');
      }
      return result.data!;
    } on MissingPluginException {
      return _fallbackClient.createDedicatedCalendar(
        name: name,
        colorHex: colorHex,
      );
    }
  }

  @override
  Future<List<ExternalCalendarEvent>> retrieveEvents({
    required String calendarId,
    required TimeRange range,
  }) async {
    if (!_supportsNativeDeviceCalendar) {
      return _fallbackClient.retrieveEvents(
        calendarId: calendarId,
        range: range,
      );
    }

    try {
      final params = RetrieveEventsParams(
        startDate: range.start,
        endDate: range.end,
      );
      final result = await _plugin.retrieveEvents(calendarId, params);
      final events = result.data ?? const <Event>[];

      final List<ExternalCalendarEvent> mapped = [];
      for (final evt in events) {
        final start = evt.start;
        final end = evt.end;
        if (start == null || end == null || !end.isAfter(start)) continue;

        mapped.add(
          ExternalCalendarEvent(
            externalEventId: evt.eventId,
            calendarId: calendarId,
            title: evt.title ?? 'Busy',
            description: evt.description,
            timeRange: TimeRange(
              start: DateTime.fromMillisecondsSinceEpoch(
                start.millisecondsSinceEpoch,
              ),
              end: DateTime.fromMillisecondsSinceEpoch(
                end.millisecondsSinceEpoch,
              ),
            ),
          ),
        );
      }
      return mapped;
    } on MissingPluginException {
      return _fallbackClient.retrieveEvents(
        calendarId: calendarId,
        range: range,
      );
    }
  }

  @override
  Future<String> createOrUpdateEvent(ExternalCalendarEvent event) async {
    if (!_supportsNativeDeviceCalendar) {
      return _fallbackClient.createOrUpdateEvent(event);
    }

    try {
      final location = tz.local;
      final deviceEvent = Event(
        event.calendarId,
        eventId: event.externalEventId,
        title: event.title,
        description: event.description,
        start: tz.TZDateTime.from(event.timeRange.start, location),
        end: tz.TZDateTime.from(event.timeRange.end, location),
        reminders: [
          Reminder(minutes: event.reminderMinutesBefore),
        ],
      );

      final result = await _plugin.createOrUpdateEvent(deviceEvent);
      if (result == null || !result.isSuccess || result.data == null) {
        throw StateError(
          'Failed to write event "${event.title}" to calendar ${event.calendarId}.',
        );
      }
      return result.data!;
    } on MissingPluginException {
      return _fallbackClient.createOrUpdateEvent(event);
    }
  }

  @override
  Future<bool> deleteEvent({
    required String calendarId,
    required String externalEventId,
  }) async {
    if (!_supportsNativeDeviceCalendar) {
      return _fallbackClient.deleteEvent(
        calendarId: calendarId,
        externalEventId: externalEventId,
      );
    }

    try {
      final result = await _plugin.deleteEvent(calendarId, externalEventId);
      return result.isSuccess && (result.data ?? false);
    } on MissingPluginException {
      return _fallbackClient.deleteEvent(
        calendarId: calendarId,
        externalEventId: externalEventId,
      );
    }
  }

  static Color _hexToColor(String hex) {
    final cleaned = hex.replaceAll('#', '');
    final buffer = StringBuffer();
    if (cleaned.length == 6) buffer.write('ff');
    buffer.write(cleaned);
    final intVal = int.tryParse(buffer.toString(), radix: 16) ?? 0xFF2196F3;
    return Color(intVal);
  }

  static String _intColorToHex(int? colorValue) {
    if (colorValue == null) return '#2196F3';
    final rgb = colorValue & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}
