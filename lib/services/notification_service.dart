import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../models/notification_item.dart';

class NotificationService extends ChangeNotifier {
  final List<NotificationItem> _notifications = [];
  final StreamController<List<NotificationItem>> _controller =
      StreamController<List<NotificationItem>>.broadcast();

  Stream<List<NotificationItem>> get notificationsStream => _controller.stream;
  List<NotificationItem> get notifications => List.unmodifiable(_notifications);
  String? _registeredDeviceToken;
  String? get registeredDeviceToken => _registeredDeviceToken;

  NotificationService() {
    // Seed initial notification
    _notifications.add(
      NotificationItem(
        notificationId: 'notif_init',
        userId: 'all',
        title: 'Welcome to EdhiConnect AI',
        message: 'Your emergency response and humanitarian portal is active.',
        type: 'general',
        createdAt: DateTime.now(),
      ),
    );
    _controller.add(_notifications);
    _initializeForegroundMessaging();
  }

  Future<void> _initializeForegroundMessaging() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        registerDeviceToken(await messaging.getToken() ?? '');
      }
      FirebaseMessaging.instance.onTokenRefresh.listen(registerDeviceToken);
      FirebaseMessaging.onMessage.listen(_receiveFirebaseMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_receiveFirebaseMessage);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _receiveFirebaseMessage(initial);
    } catch (error) {
      debugPrint('Push messaging initialization notice: $error');
    }
  }

  Future<bool> requestPushPermission() async {
    if (Firebase.apps.isEmpty) return false;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      final allowed =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (allowed) {
        registerDeviceToken(await FirebaseMessaging.instance.getToken() ?? '');
      }
      return allowed;
    } catch (error) {
      debugPrint('Push permission request failed: $error');
      return false;
    }
  }

  void _receiveFirebaseMessage(RemoteMessage message) {
    receiveRemoteNotification({
      ...message.data,
      'title': message.notification?.title ?? message.data['title'],
      'body': message.notification?.body ?? message.data['body'],
    });
  }

  void sendNotification({
    required String userId,
    required String title,
    required String message,
    String type = 'general',
  }) {
    final item = NotificationItem(
      notificationId: 'notif_${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      title: title,
      message: message,
      type: type,
      createdAt: DateTime.now(),
    );
    _notifications.insert(0, item);
    _controller.add(_notifications);
    notifyListeners();
  }

  /// Registers the token obtained from FCM/APNs. The token can then be stored
  /// through FirestoreService.registerPushToken and targeted by a trusted
  /// Cloud Function without placing server credentials in the mobile app.
  void registerDeviceToken(String token) {
    final normalized = token.trim();
    if (normalized.isEmpty || normalized == _registeredDeviceToken) return;
    _registeredDeviceToken = normalized;
    notifyListeners();
  }

  /// Converts a foreground push payload into the same inbox model used by
  /// local dispatch alerts, keeping notification UI consistent.
  void receiveRemoteNotification(Map<String, dynamic> payload) {
    final title = payload['title']?.toString().trim();
    final message =
        payload['message']?.toString().trim() ??
        payload['body']?.toString().trim();
    if (title == null || title.isEmpty || message == null || message.isEmpty) {
      return;
    }
    sendNotification(
      userId: payload['userId']?.toString() ?? 'all',
      title: title,
      message: message,
      type: payload['type']?.toString() ?? 'general',
    );
  }

  void markAsRead(String notificationId) {
    final index = _notifications.indexWhere(
      (n) => n.notificationId == notificationId,
    );
    if (index != -1) {
      final current = _notifications[index];
      _notifications[index] = NotificationItem(
        notificationId: current.notificationId,
        userId: current.userId,
        title: current.title,
        message: current.message,
        type: current.type,
        isRead: true,
        createdAt: current.createdAt,
      );
      _controller.add(_notifications);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }
}
