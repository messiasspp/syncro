import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:http/http.dart' as http;

import '../../domain/models/external_calendar.dart';
import '../../domain/models/time_range.dart';

/// Authenticated Google Calendar REST v3 service using `google_sign_in`,
/// native Android `AccountManager`, or a manual OAuth2 Bearer token.
///
/// Enables Syncro to create real cloud-synced `com.google` secondary
/// calendars (e.g. "Friends") that immediately sync across Mobile and Desktop
/// Web Google Calendar, and forces Android's native ContentResolver to pull
/// newly created calendars down to the device right away.
class GoogleCloudCalendarService {
  static const String configuredProjectId = 'gen-lang-client-0582172535';
  static const String configuredAndroidClientId =
      '10792409478-c798n2sloqf79nvngccp6feko39nccbi.apps.googleusercontent.com';

  static const MethodChannel _syncChannel =
      MethodChannel('com.example.syncro/google_calendar_sync');

  static const List<String> _scopes = [gcal.CalendarApi.calendarScope];

  GoogleSignIn? _googleSignIn;
  GoogleSignInAccount? _googleAccount;
  String? _accessToken;
  String? _signedInEmail;

  bool get isSignedIn => _accessToken != null || _googleAccount != null;

  String? get signedInEmail => _googleAccount?.email ?? _signedInEmail;

  GoogleSignIn _ensureGoogleSignIn() {
    return _googleSignIn ??= GoogleSignIn(scopes: _scopes);
  }

  /// Restores a previously granted Google Sign-In session silently if available.
  Future<bool> tryRestoreSilentSignIn() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return false;
    }
    try {
      final account = await _ensureGoogleSignIn().signInSilently();
      if (account != null) {
        _googleAccount = account;
        _signedInEmail = account.email;
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Authenticates interactively using Google Play Services (`GoogleSignIn`),
  /// falling back to Android's OS `AccountManager` if Play Services throws a
  /// [PlatformException].
  Future<String?> signInInteractive({String? preferredEmail}) async {
    try {
      final account = await _ensureGoogleSignIn().signIn();
      if (account != null) {
        _googleAccount = account;
        _signedInEmail = account.email;
        return account.email;
      }
      return null;
    } on PlatformException {
      if (!kIsWeb &&
          Platform.isAndroid &&
          preferredEmail != null &&
          preferredEmail.contains('@')) {
        try {
          final token = await _syncChannel.invokeMethod<String>(
            'acquireAccountToken',
            {'email': preferredEmail.trim()},
          );
          if (token != null && token.trim().isNotEmpty) {
            _accessToken = token.trim();
            _signedInEmail = preferredEmail.trim();
            return _signedInEmail;
          }
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Activates cloud access directly with an OAuth2 Bearer access token.
  void setManualAccessToken(String token, {String? email}) {
    final cleaned = token.trim();
    if (cleaned.isEmpty) {
      throw ArgumentError('OAuth2 access token cannot be empty.');
    }
    _accessToken = cleaned;
    _signedInEmail = (email != null && email.trim().isNotEmpty)
        ? email.trim()
        : 'Google Cloud';
  }

  /// Signs out from Google Cloud API sessions and clears local tokens.
  Future<void> signOut() async {
    _accessToken = null;
    _signedInEmail = null;
    _googleAccount = null;
    try {
      await _googleSignIn?.signOut();
    } catch (_) {}
  }

  /// Requests an expedited native Android `ContentResolver` sync so any newly
  /// created cloud calendars immediately appear in the device CalendarProvider
  /// and Mobile Google Calendar app.
  Future<void> triggerNativeAndroidSync([String? email]) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _syncChannel.invokeMethod<bool>(
        'requestCalendarSync',
        {'email': email ?? signedInEmail},
      );
    } on MissingPluginException {
      // Desktop / unit test environment
    } catch (_) {}
  }

  Future<gcal.CalendarApi> _apiClient() async {
    if (_accessToken != null) {
      final authClient = _BearerAuthClient(
        staticToken: _accessToken,
      );
      return gcal.CalendarApi(authClient);
    }
    final acct = _googleAccount;
    if (acct != null) {
      final headers = await acct.authHeaders;
      final authClient = _BearerAuthClient(staticHeaders: headers);
      return gcal.CalendarApi(authClient);
    }
    throw StateError('Not signed in to Google Calendar Cloud API.');
  }

  /// Lists every Google Calendar visible in the authenticated user's account.
  Future<List<ExternalCalendar>> listCloudCalendars() async {
    final api = await _apiClient();
    final response = await api.calendarList.list(showHidden: false);
    final items = response.items ?? const <gcal.CalendarListEntry>[];
    final acctEmail = signedInEmail;

    return [
      for (final entry in items)
        if (entry.id != null)
          ExternalCalendar(
            id: entry.id!,
            name: (entry.summaryOverride?.trim().isNotEmpty ?? false)
                ? entry.summaryOverride!.trim()
                : (entry.summary ?? 'Google Calendar'),
            accountName: acctEmail,
            colorHex: _normalizeRgbHex(entry.backgroundColor ?? '#4285F4'),
            isReadOnly:
                entry.accessRole != 'owner' && entry.accessRole != 'writer',
          ),
    ];
  }

  /// Lists secondary cloud Google Calendars created by Syncro (including demo
  /// calendars such as 'Friends Zone' and 'Mounjaro Clinical Study').
  Future<List<ExternalCalendar>> listSyncroManagedCloudCalendars() async {
    final api = await _apiClient();
    final response = await api.calendarList.list(showHidden: true);
    final items = response.items ?? const <gcal.CalendarListEntry>[];
    final acctEmail = signedInEmail;

    return [
      for (final entry in items)
        if (entry.id != null &&
            entry.primary != true &&
            (entry.accessRole == 'owner' || entry.accessRole == 'writer') &&
            ((entry.description?.contains('Syncro') ?? false) ||
                (entry.summary?.trim() == 'Friends Zone') ||
                (entry.summary?.trim() == 'Mounjaro Clinical Study')))
          ExternalCalendar(
            id: entry.id!,
            name: (entry.summaryOverride?.trim().isNotEmpty ?? false)
                ? entry.summaryOverride!.trim()
                : (entry.summary ?? 'Google Calendar'),
            accountName: acctEmail,
            colorHex: _normalizeRgbHex(entry.backgroundColor ?? '#4285F4'),
            isReadOnly: false,
          ),
    ];
  }

  /// Ensures a real secondary cloud Google Calendar named [name] exists in the
  /// user's Google account (reusing any matching writable calendar if found).
  Future<ExternalCalendar> ensureCloudCalendar({
    required String name,
    required String colorHex,
  }) async {
    final api = await _apiClient();
    final targetNorm = name.trim().toLowerCase();

    final listRes = await api.calendarList.list();
    for (final entry in listRes.items ?? const <gcal.CalendarListEntry>[]) {
      final summaryMatch =
          (entry.summary?.trim().toLowerCase() ?? '') == targetNorm;
      final overrideMatch =
          (entry.summaryOverride?.trim().toLowerCase() ?? '') == targetNorm;
      final isWritable =
          entry.accessRole == 'owner' || entry.accessRole == 'writer';
      if ((summaryMatch || overrideMatch) && isWritable && entry.id != null) {
        return ExternalCalendar(
          id: entry.id!,
          name: entry.summaryOverride ?? entry.summary ?? name,
          accountName: signedInEmail,
          colorHex: _normalizeRgbHex(entry.backgroundColor ?? colorHex),
          isReadOnly: false,
        );
      }
    }

    final created = await api.calendars.insert(
      gcal.Calendar(
        summary: name.trim(),
        description: 'Managed by Syncro Smart Scheduler',
      ),
    );
    final createdId = created.id!;
    final normalizedHex = _normalizeRgbHex(colorHex);

    try {
      await api.calendarList.patch(
        gcal.CalendarListEntry(
          backgroundColor: normalizedHex,
          foregroundColor: '#ffffff',
          selected: true,
        ),
        createdId,
        colorRgbFormat: true,
      );
    } catch (_) {
      // Color patching is best-effort; calendar creation succeeded regardless
    }

    await triggerNativeAndroidSync(signedInEmail);

    return ExternalCalendar(
      id: createdId,
      name: created.summary ?? name.trim(),
      accountName: signedInEmail,
      colorHex: normalizedHex,
      isReadOnly: false,
    );
  }

  /// Retrieves Google Calendar events from cloud calendar [calendarId] in [range].
  Future<List<ExternalCalendarEvent>> retrieveCloudEvents({
    required String calendarId,
    required TimeRange range,
  }) async {
    final api = await _apiClient();
    final events = await api.events.list(
      calendarId,
      timeMin: range.start.toUtc(),
      timeMax: range.end.toUtc(),
      singleEvents: true,
      orderBy: 'startTime',
      maxResults: 250,
    );

    final List<ExternalCalendarEvent> mapped = [];
    for (final item in events.items ?? const <gcal.Event>[]) {
      final startDt = item.start?.dateTime ?? item.start?.date;
      final endDt = item.end?.dateTime ?? item.end?.date;
      if (startDt == null || endDt == null) continue;
      final localStart = startDt.toLocal();
      final localEnd = endDt.toLocal();
      if (!localEnd.isAfter(localStart)) continue;

      mapped.add(
        ExternalCalendarEvent(
          externalEventId: item.id,
          calendarId: calendarId,
          title: item.summary ?? 'Busy',
          description: item.description,
          timeRange: TimeRange(start: localStart, end: localEnd),
        ),
      );
    }
    return mapped;
  }

  /// Extracts Syncro's embedded appointment ID from an event description.
  static String? extractSyncroAppointmentId(String? description) {
    if (description == null || description.isEmpty) return null;
    return RegExp(r'SyncroAppointmentId:\s*(\S+)')
        .firstMatch(description)
        ?.group(1)
        ?.trim();
  }

  /// Extracts the Participant line from a Syncro event description.
  static String? extractParticipantLine(String? description) {
    if (description == null || description.isEmpty) return null;
    return RegExp(r'^Participant:\s*(.+)$', multiLine: true)
        .firstMatch(description)
        ?.group(1)
        ?.trim();
  }

  /// Extracts the portion of a Syncro event title after ` - ` or ` — `.
  static String? extractTitleSuffix(String? title) {
    if (title == null || title.isEmpty) return null;
    final sepIdx = title.contains(' - ')
        ? title.indexOf(' - ')
        : title.indexOf(' — ');
    if (sepIdx < 0) return null;
    return title.substring(sepIdx + 3).trim();
  }

  /// Inserts or updates an event directly in Google Cloud Calendar [event.calendarId],
  /// matching existing Syncro events in the same slot so code/calendar changes update
  /// in place and never leave duplicate events behind.
  Future<String> createOrUpdateCloudEvent(ExternalCalendarEvent event) async {
    final api = await _apiClient();
    final gEvent = gcal.Event(
      summary: event.title,
      description: event.description,
      start: gcal.EventDateTime(dateTime: event.timeRange.start.toUtc()),
      end: gcal.EventDateTime(dateTime: event.timeRange.end.toUtc()),
      reminders: gcal.EventReminders(
        useDefault: false,
        overrides: [
          gcal.EventReminder(
            method: 'popup',
            minutes: event.reminderMinutesBefore,
          ),
        ],
      ),
    );

    gcal.Event? saved;
    final extId = event.externalEventId;
    if (extId != null && extId.isNotEmpty) {
      try {
        saved = await api.events.update(gEvent, event.calendarId, extId);
      } catch (_) {
        saved = null;
      }
    }

    if (saved == null) {
      final expectedAptId = extractSyncroAppointmentId(event.description);
      final expectedParticipant = extractParticipantLine(event.description);
      final expectedSuffix = extractTitleSuffix(event.title);
      final List<gcal.Event> slotMatches = [];

      try {
        final nearby = await api.events.list(
          event.calendarId,
          timeMin: event.timeRange.start
              .subtract(const Duration(minutes: 1))
              .toUtc(),
          timeMax:
              event.timeRange.end.add(const Duration(minutes: 1)).toUtc(),
          singleEvents: true,
        );
        for (final candidate in nearby.items ?? const <gcal.Event>[]) {
          final candId = candidate.id;
          if (candId == null) continue;
          final candDesc = candidate.description;
          final candAptId = extractSyncroAppointmentId(candDesc);
          final isSyncroDesc = candDesc != null &&
              candDesc.contains('Scheduled via Syncro Smart Engine');
          final sameAptId = expectedAptId != null && candAptId == expectedAptId;
          final sameParticipant = isSyncroDesc &&
              expectedParticipant != null &&
              extractParticipantLine(candDesc) == expectedParticipant;
          final sameSuffix = isSyncroDesc &&
              expectedSuffix != null &&
              extractTitleSuffix(candidate.summary) == expectedSuffix;
          if (sameAptId || sameParticipant || sameSuffix) {
            slotMatches.add(candidate);
          }
        }
      } catch (_) {}

      if (slotMatches.isNotEmpty) {
        final primaryMatch = slotMatches.first;
        saved = await api.events.update(
          gEvent,
          event.calendarId,
          primaryMatch.id!,
        );
        // Clean up any duplicate Syncro copies already sitting in the same slot
        for (var i = 1; i < slotMatches.length; i++) {
          final dupId = slotMatches[i].id;
          if (dupId != null && dupId != saved.id) {
            try {
              await api.events.delete(event.calendarId, dupId);
            } catch (_) {}
          }
        }
      } else {
        saved = await api.events.insert(gEvent, event.calendarId);
      }
    }

    await triggerNativeAndroidSync(signedInEmail);
    return saved.id!;
  }

  /// Deletes a Google Calendar event via REST v3 API.
  Future<bool> deleteCloudEvent({
    required String calendarId,
    required String externalEventId,
  }) async {
    final api = await _apiClient();
    await api.events.delete(calendarId, externalEventId);
    await triggerNativeAndroidSync(signedInEmail);
    return true;
  }

  /// Deletes a secondary cloud calendar via REST v3 API.
  Future<bool> deleteCloudCalendar(String calendarId) async {
    final api = await _apiClient();
    await api.calendars.delete(calendarId);
    await triggerNativeAndroidSync(signedInEmail);
    return true;
  }

  static String _normalizeRgbHex(String hex) {
    var cleaned = hex.trim().replaceAll('#', '');
    if (cleaned.length == 8) {
      cleaned = cleaned.substring(2);
    }
    if (cleaned.length != 6) {
      return '#4285f4';
    }
    return '#${cleaned.toLowerCase()}';
  }
}

class _BearerAuthClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final String? staticToken;
  final Map<String, String>? staticHeaders;

  _BearerAuthClient({this.staticToken, this.staticHeaders});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (staticHeaders != null) {
      request.headers.addAll(staticHeaders!);
    } else if (staticToken != null) {
      request.headers['Authorization'] = 'Bearer $staticToken';
    }
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
  }
}
