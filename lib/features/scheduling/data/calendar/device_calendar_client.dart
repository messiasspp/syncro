import 'dart:io';

import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../domain/models/external_calendar.dart';
import '../../domain/models/time_range.dart';
import 'calendar_client.dart';
import 'google_cloud_calendar_service.dart';

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
  final GoogleCloudCalendarService? _cloudService;

  NativeDeviceCalendarClient({
    DeviceCalendarPlugin? plugin,
    InMemoryCalendarClient? fallbackClient,
    GoogleCloudCalendarService? cloudService,
  })  : _plugin = plugin ?? DeviceCalendarPlugin(),
        _fallbackClient = fallbackClient ?? InMemoryCalendarClient(),
        _cloudService = cloudService;

  bool get _isCloudReady => _cloudService != null && _cloudService.isSignedIn;

  static bool _isCloudCalendarId(String id) => id.contains('@');

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
    final List<ExternalCalendar> validCalendars = [];

    if (!_supportsNativeDeviceCalendar) {
      validCalendars.addAll(await _fallbackClient.retrieveCalendars());
    } else {
      try {
        final result = await _plugin.retrieveCalendars();
        final calendars = result.data ?? const <Calendar>[];
        for (final c in calendars) {
          if (c.id == null) continue;
          // Automatically purge legacy offline 'Syncro' sub-calendars while preserving
          // any cloud Google calendar explicitly named 'Syncro'.
          if (c.accountName == 'Syncro' ||
              c.accountName == 'Syncro Local' ||
              (c.name != null && c.name!.startsWith('Syncro —'))) {
            try {
              await _plugin.deleteCalendar(c.id!);
            } catch (_) {}
            continue;
          }
          validCalendars.add(
            ExternalCalendar(
              id: c.id!,
              name: c.name ?? 'Unnamed Calendar',
              accountName: c.accountName,
              colorHex: _intColorToHex(c.color),
              isReadOnly: c.isReadOnly ?? false,
            ),
          );
        }
      } on MissingPluginException {
        validCalendars.addAll(await _fallbackClient.retrieveCalendars());
      }
    }

    if (_isCloudReady) {
      try {
        final cloudCals = await _cloudService!.listCloudCalendars();
        final existingIds = validCalendars.map((c) => c.id).toSet();
        final existingNames =
            validCalendars.map((c) => c.name.trim().toLowerCase()).toSet();
        for (final cal in cloudCals) {
          if (!existingIds.contains(cal.id) &&
              !existingNames.contains(cal.name.trim().toLowerCase())) {
            validCalendars.add(cal);
          }
        }
      } catch (_) {}
    }

    return validCalendars;
  }

  @override
  Future<List<ExternalCalendar>> retrieveRawCalendars() async {
    if (!_supportsNativeDeviceCalendar) {
      return _fallbackClient.retrieveRawCalendars();
    }

    try {
      final result = await _plugin.retrieveCalendars();
      final calendars = result.data ?? const <Calendar>[];
      return [
        for (final c in calendars)
          if (c.id != null)
            ExternalCalendar(
              id: c.id!,
              name: c.name ?? 'Unnamed Calendar',
              accountName: c.accountName,
              colorHex: _intColorToHex(c.color),
              isReadOnly: c.isReadOnly ?? false,
            ),
      ];
    } on MissingPluginException {
      return _fallbackClient.retrieveRawCalendars();
    }
  }

  @override
  Future<bool> deleteCalendar(String calendarId) async {
    if (_isCloudReady && _isCloudCalendarId(calendarId)) {
      try {
        return await _cloudService!.deleteCloudCalendar(calendarId);
      } catch (_) {}
    }

    if (!_supportsNativeDeviceCalendar) {
      return _fallbackClient.deleteCalendar(calendarId);
    }

    try {
      final result = await _plugin.deleteCalendar(calendarId);
      return result.isSuccess && (result.data ?? false);
    } on MissingPluginException {
      return _fallbackClient.deleteCalendar(calendarId);
    }
  }

  @override
  Future<String> createDedicatedCalendar({
    required String name,
    required String colorHex,
  }) async {
    final targetNorm = name.trim().toLowerCase();
    final existing = await retrieveCalendars();
    for (final cal in existing) {
      if (cal.name.trim().toLowerCase() == targetNorm && !cal.isReadOnly) {
        return cal.id;
      }
    }

    if (_isCloudReady) {
      final cloudCal = await _cloudService!.ensureCloudCalendar(
        name: name,
        colorHex: colorHex,
      );
      if (_supportsNativeDeviceCalendar) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        try {
          final nativeRes = await _plugin.retrieveCalendars();
          for (final c in nativeRes.data ?? const <Calendar>[]) {
            if (c.id != null &&
                !(c.isReadOnly ?? false) &&
                (c.name?.trim().toLowerCase() ?? '') == targetNorm &&
                c.accountName != 'Syncro' &&
                c.accountName != 'Syncro Local') {
              return c.id!;
            }
          }
        } catch (_) {}
      }
      return cloudCal.id;
    }

    if (!_supportsNativeDeviceCalendar) {
      return _fallbackClient.createDedicatedCalendar(
        name: name,
        colorHex: colorHex,
      );
    }

    try {
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
    if (_isCloudReady && _isCloudCalendarId(calendarId)) {
      return _cloudService!.retrieveCloudEvents(
        calendarId: calendarId,
        range: range,
      );
    }

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
    if (_isCloudReady && _isCloudCalendarId(event.calendarId)) {
      return _cloudService!.createOrUpdateCloudEvent(event);
    }

    if (!_supportsNativeDeviceCalendar) {
      return _fallbackClient.createOrUpdateEvent(event);
    }

    try {
      final location = tz.local;
      final expectedAptId =
          GoogleCloudCalendarService.extractSyncroAppointmentId(
        event.description,
      );
      final expectedParticipant =
          GoogleCloudCalendarService.extractParticipantLine(event.description);
      final expectedSuffix =
          GoogleCloudCalendarService.extractTitleSuffix(event.title);

      String? targetEventId = event.externalEventId;
      final windowEventsRes = await _plugin.retrieveEvents(
        event.calendarId,
        RetrieveEventsParams(
          startDate: event.timeRange.start.subtract(const Duration(minutes: 5)),
          endDate: event.timeRange.end.add(const Duration(minutes: 5)),
        ),
      );
      final windowEvents = windowEventsRes.data ?? const <Event>[];
      final hasExactTarget = targetEventId != null &&
          windowEvents.any((e) => e.eventId == targetEventId);

      final List<Event> slotMatches = [];
      for (final e in windowEvents) {
        if (e.eventId == null) continue;
        final isSyncroDesc = e.description != null &&
            e.description!.contains('Scheduled via Syncro Smart Engine');
        final candAptId =
            GoogleCloudCalendarService.extractSyncroAppointmentId(
          e.description,
        );
        final sameAptId = expectedAptId != null && candAptId == expectedAptId;
        final sameParticipant = isSyncroDesc &&
            expectedParticipant != null &&
            GoogleCloudCalendarService.extractParticipantLine(e.description) ==
                expectedParticipant;
        final sameSuffix = isSyncroDesc &&
            expectedSuffix != null &&
            GoogleCloudCalendarService.extractTitleSuffix(e.title) ==
                expectedSuffix;
        final eStart = e.start;
        final withinMinute = eStart != null &&
            DateTime.fromMillisecondsSinceEpoch(eStart.millisecondsSinceEpoch)
                    .difference(event.timeRange.start)
                    .abs() <=
                const Duration(minutes: 1);
        if (e.eventId == targetEventId ||
            sameAptId ||
            ((sameParticipant || sameSuffix) && withinMinute)) {
          slotMatches.add(e);
        }
      }

      if (!hasExactTarget) {
        targetEventId =
            slotMatches.isNotEmpty ? slotMatches.first.eventId : null;
      }

      final deviceEvent = Event(
        event.calendarId,
        eventId: targetEventId,
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
      final savedId = result.data!;
      for (final dup in slotMatches) {
        final dupId = dup.eventId;
        if (dupId != null && dupId != savedId) {
          try {
            await _plugin.deleteEvent(event.calendarId, dupId);
          } catch (_) {}
        }
      }
      return savedId;
    } on MissingPluginException {
      return _fallbackClient.createOrUpdateEvent(event);
    }
  }

  @override
  Future<bool> deleteEvent({
    required String calendarId,
    required String externalEventId,
  }) async {
    if (_isCloudReady && _isCloudCalendarId(calendarId)) {
      return _cloudService!.deleteCloudEvent(
        calendarId: calendarId,
        externalEventId: externalEventId,
      );
    }

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
