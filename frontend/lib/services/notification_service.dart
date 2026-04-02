import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:safeher/constants/app_theme.dart';

/// Notification Service for SafeHer
/// Handles all local push notifications for SOS alerts and app status
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  // Notification Channel IDs
  static const String _sosChannelId = 'safeher_sos_alerts';
  static const String _sosChannelName = 'SOS Alerts';
  static const String _sosChannelDesc =
      'Critical emergency alerts when SOS is triggered';

  static const String _statusChannelId = 'safeher_status';
  static const String _statusChannelName = 'Connection Status';
  static const String _statusChannelDesc =
      'Notifications about device connection status';

  static const String _reminderChannelId = 'safeher_reminders';
  static const String _reminderChannelName = 'Safety Reminders';
  static const String _reminderChannelDesc =
      'Reminders to stay safe and check your device';

  // Notification IDs
  static const int sosNotificationId = 1001;
  static const int connectionNotificationId = 1002;
  static const int reminderNotificationId = 1003;
  static const int cancelledNotificationId = 1004;

  /// Initialize the notification service
  Future<void> initialize({
    void Function(NotificationResponse)? onNotificationTap,
  }) async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: onNotificationTap,
    );

    // Create notification channels for Android
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }

    _isInitialized = true;
  }

  Future<void> _createNotificationChannels() async {
    final androidPlugin =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return;

    // SOS Alerts Channel - Highest priority
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _sosChannelId,
        _sosChannelName,
        description: _sosChannelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: AppTheme.primaryColor,
      ),
    );

    // Status Channel
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _statusChannelId,
        _statusChannelName,
        description: _statusChannelDesc,
        importance: Importance.defaultImportance,
      ),
    );

    // Reminders Channel
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _reminderChannelId,
        _reminderChannelName,
        description: _reminderChannelDesc,
        importance: Importance.low,
      ),
    );
  }

  /// Show SOS triggered notification
  Future<void> showSOSTriggered({
    required int contactCount,
    String? locationInfo,
  }) async {
    final body = contactCount > 0
        ? 'Emergency alert sent to $contactCount contact${contactCount > 1 ? 's' : ''}. '
            '${locationInfo ?? 'Location shared.'}'
        : 'SOS triggered but no contacts configured!';

    await _notifications.show(
      sosNotificationId,
      '🚨 SOS ALERT TRIGGERED',
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _sosChannelId,
          _sosChannelName,
          channelDescription: _sosChannelDesc,
          importance: Importance.max,
          priority: Priority.max,
          color: AppTheme.primaryColor,
          enableVibration: true,
          playSound: true,
          ongoing: true,
          autoCancel: false,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          visibility: NotificationVisibility.public,
          actions: [
            const AndroidNotificationAction(
              'cancel_sos',
              'I\'m Safe',
              showsUserInterface: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.critical,
        ),
      ),
    );
  }

  /// Show SOS cancelled notification
  Future<void> showSOSCancelled() async {
    // Cancel the ongoing SOS notification
    await _notifications.cancel(sosNotificationId);

    await _notifications.show(
      cancelledNotificationId,
      '✅ SOS Cancelled',
      'Alert cancelled. Your contacts have been notified that you are safe.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _sosChannelId,
          _sosChannelName,
          channelDescription: _sosChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
          color: AppTheme.success,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  /// Show device connected notification
  Future<void> showDeviceConnected(String deviceName) async {
    await _notifications.show(
      connectionNotificationId,
      '🔗 Keychain Connected',
      '$deviceName is now connected. SafeHer is ready to protect you.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _statusChannelId,
          _statusChannelName,
          channelDescription: _statusChannelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          color: AppTheme.success,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
    );
  }

  /// Show device disconnected notification
  Future<void> showDeviceDisconnected(String deviceName) async {
    await _notifications.show(
      connectionNotificationId,
      '⚠️ Keychain Disconnected',
      '$deviceName lost connection. Please reconnect to stay protected.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _statusChannelId,
          _statusChannelName,
          channelDescription: _statusChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
          color: AppTheme.warning,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  /// Show safety reminder notification
  Future<void> showSafetyReminder({
    required String title,
    required String message,
  }) async {
    await _notifications.show(
      reminderNotificationId,
      title,
      message,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _reminderChannelId,
          _reminderChannelName,
          channelDescription: _reminderChannelDesc,
          importance: Importance.low,
          priority: Priority.low,
          color: AppTheme.info,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
        ),
      ),
    );
  }

  /// Cancel a specific notification
  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  /// Request notification permissions (for iOS 10+)
  Future<bool> requestPermissions() async {
    if (Platform.isIOS) {
      final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final result = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
        critical: true,
      );
      return result ?? false;
    }

    if (Platform.isAndroid) {
      final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final result = await androidPlugin?.requestNotificationsPermission();
      return result ?? false;
    }

    return true;
  }
}
