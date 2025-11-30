import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Android initialization
      const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');

      // iOS initialization
      const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      // macOS initialization
      const DarwinInitializationSettings macSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
        macOS: macSettings,
      );

      await _notifications.initialize(initSettings);
      _initialized = true;
    } catch (e) {
      // Silent fail - notifications are non-critical
    }
  }

  Future<void> showDownloadComplete({
    required String fileName,
    required String filePath,
  }) async {
    if (!_initialized) await initialize();

    try {
      // Request permissions on iOS/macOS
      if (Platform.isIOS || Platform.isMacOS) {
        await _notifications
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            );
      }

      // Android notification details
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'downloads',
        'Downloads',
        channelDescription: 'File download notifications',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/launcher_icon',
        color: Color(0xFF34A853),
        playSound: true,
        enableVibration: true,
      );

      // iOS/macOS notification details
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        macOS: iosDetails,
      );

      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch % 100000,
        'Download Complete',
        '$fileName saved to ${_getReadablePath(filePath)}',
        details,
      );
    } catch (e) {
      // Silent fail - notifications are non-critical
    }
  }

  Future<void> showDownloadError({
    required String fileName,
    required String error,
  }) async {
    if (!_initialized) await initialize();

    try {
      // Request permissions on iOS/macOS
      if (Platform.isIOS || Platform.isMacOS) {
        await _notifications
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            );
      }

      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'downloads',
        'Downloads',
        channelDescription: 'File download notifications',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/launcher_icon',
        color: Color(0xFFD32F2F),
        playSound: true,
        enableVibration: true,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        macOS: iosDetails,
      );

      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch % 100000,
        'Download Failed',
        'Failed to download $fileName',
        details,
      );
    } catch (e) {
      // Silent fail - notifications are non-critical
    }
  }

  String _getReadablePath(String path) {
    if (path.contains('/Download/DecVault')) {
      return 'Downloads/DecVault';
    } else if (path.contains('/Downloads/')) {
      return 'Downloads';
    } else if (path.contains('/Documents/')) {
      return 'Documents';
    } else if (path.contains('/Pictures/')) {
      return 'Pictures';
    } else if (path.contains('/Movies/')) {
      return 'Movies';
    }
    return 'device storage';
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}

