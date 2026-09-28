import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_log.dart';

// Must be a top-level function. When the app is in the background or terminated
// the OS displays the notification from the tray — nothing to do here.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Thin wrapper around Firebase Messaging + local notifications so the rest of
/// the app only deals with "init" and "get token".
class PushNotifications {
  PushNotifications._();
  static final PushNotifications instance = PushNotifications._();

  static const _channelId = 'campus_tracker_default';
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  AuthorizationStatus? _authorization;

  /// Whether the user actually allowed notifications. False means nothing will
  /// ever be displayed no matter how many pushes the backend sends, so this is
  /// the first thing to check when "notifications aren't arriving".
  bool get permissionGranted =>
      _authorization == AuthorizationStatus.authorized ||
      _authorization == AuthorizationStatus.provisional;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // The result used to be discarded, which made a denied permission
    // completely invisible — the app looked healthy and registered a valid
    // token, but the OS dropped every notification. On Android this needs
    // POST_NOTIFICATIONS in AndroidManifest.xml or no dialog is even shown.
    final settings = await FirebaseMessaging.instance.requestPermission();
    _authorization = settings.authorizationStatus;
    sessionLog('notification permission: ${settings.authorizationStatus.name}');
    if (!permissionGranted) {
      sessionLog(
        'NOTIFICATIONS WILL NOT BE DISPLAYED — permission not granted. '
        'The user must enable them in system settings; re-requesting will not '
        're-prompt once permanently denied.',
      );
    }

    const androidChannel = AndroidNotificationChannel(
      _channelId,
      'Adimove',
      description: 'Pickup, drop-off and fee notifications',
      importance: Importance.high,
    );

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    // Foreground messages don't auto-display — show them ourselves.
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      _local.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Adimove',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    });
  }

  Future<String?> token() async {
    if (Platform.isIOS) {
      // iOS needs the APNs token resolved before the FCM token is available.
      await FirebaseMessaging.instance.getAPNSToken();
    }
    return FirebaseMessaging.instance.getToken();
  }

  Stream<String> get onTokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;

  String get platform => Platform.isIOS ? 'ios' : 'android';
}
