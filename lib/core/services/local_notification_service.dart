import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lightweight native push notification dispatcher backed by Android's
/// `NotificationCompat` over Syncro's native platform channel.
class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.syncro/google_calendar_sync');

  Future<void> requestPermission() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      await _channel.invokeMethod<bool>('requestNotificationPermission');
    } on MissingPluginException {
      // Desktop / unit test sandbox
    } catch (_) {}
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      await _channel.invokeMethod<bool>('showLocalNotification', {
        'id': id,
        'title': title,
        'body': body,
      });
    } on MissingPluginException {
      // Desktop / unit test sandbox
    } catch (_) {}
  }
}
