import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Wires Firebase Cloud Messaging for the caregiver (doc steps 13-15):
/// permission, the max-importance "sos_alerts" channel, token registration in
/// Firestore, foreground display, and tap -> SOS screen navigation.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  static const _channel = AndroidNotificationChannel(
    'sos_alerts',
    'SOS alerts',
    description: 'Urgent emergency alerts from TruePath canes',
    importance: Importance.max,
    playSound: true,
  );

  final _local = FlutterLocalNotificationsPlugin();
  bool _wired = false;
  void Function(String alertId)? _onOpenAlert;

  Future<void> register({
    required String uid,
    required void Function(String alertId) onOpenAlert,
  }) async {
    _onOpenAlert = onOpenAlert;
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Save this phone's token so the backend can reach it (doc step 13).
    messaging.onRegistered.listen((t) => _saveToken(uid, t));
    await messaging.register();

    if (_wired) return;
    _wired = true;

    // Channel used by the backend's Android notification config.
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final alertId = response.payload;
        if (alertId != null && alertId.isNotEmpty) _onOpenAlert?.call(alertId);
      },
    );

    // Foreground: FCM does not display automatically, so we do (doc step 14).
    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n == null) return;
      _local.show(
        id: message.hashCode,
        title: n.title,
        body: n.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.max,
            priority: Priority.max,
          ),
        ),
        payload: message.data['alertId'],
      );
    });

    // Background tap (doc step 15).
    FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);

    // App launched from terminated state by a notification tap.
    final initial = await messaging.getInitialMessage();
    if (initial != null) _openFromMessage(initial);
  }

  void _openFromMessage(RemoteMessage message) {
    final alertId = message.data['alertId'];
    if (alertId != null && alertId.isNotEmpty) _onOpenAlert?.call(alertId);
  }

  Future<void> _saveToken(String uid, String token) {
    return FirebaseFirestore.instance.collection('users').doc(uid).set(
      {
        'fcmTokens': FieldValue.arrayUnion([token]),
      },
      SetOptions(merge: true),
    );
  }
}
