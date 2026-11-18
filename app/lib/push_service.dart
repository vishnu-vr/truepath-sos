import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'alarm.dart';
import 'api.dart';

/// Wires Firebase Cloud Messaging for the caregiver (doc steps 13-15):
/// permission, token registration, and routing of the SOS alarm.
///
/// SOS pushes are DATA-ONLY: the app raises the alarm itself
/// ([SosAlarm.ring]) — here in the foreground, or in
/// `firebaseBackgroundHandler` (main.dart) when backgrounded/killed.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _wired = false;
  String? _lastToken;
  void Function(String alertId)? _onAlarm;
  void Function(String alertId)? _onAck;

  /// [onAlarm] opens the alarm screen; [onAck] handles the notification's
  /// "I'm on it" action.
  Future<void> register({
    required String uid,
    required void Function(String alertId) onAlarm,
    required void Function(String alertId) onAck,
  }) async {
    _onAlarm = onAlarm;
    _onAck = onAck;
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // Save this phone's token so the backend can reach it (doc step 13).
    messaging.onRegistered.listen((t) => _saveToken(uid, t));
    await messaging.register();

    if (_wired) return;
    _wired = true;

    await SosAlarm.init(onResponse: _onResponse);

    // Foreground: ring + jump straight to the alarm screen.
    FirebaseMessaging.onMessage.listen((message) async {
      final alertId = await SosAlarm.handleData(message.data);
      if (alertId != null) _onAlarm?.call(alertId);
    });

    // App launched (cold) by the alarm: full-screen intent, a tap, or the
    // "I'm on it" action.
    final launch = await SosAlarm.plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
      _onResponse(response);
    }
  }

  void _onResponse(NotificationResponse response) {
    final alertId = response.payload;
    if (alertId == null || alertId.isEmpty) return;
    if (response.actionId == 'ack') {
      _onAck?.call(alertId);
    } else {
      _onAlarm?.call(alertId);
    }
  }

  /// Claims the token for this account via the backend, which also removes
  /// it from any OTHER account that still holds it (same phone, previous
  /// sign-in) — otherwise this phone would keep receiving alerts the current
  /// account cannot read.
  Future<void> _saveToken(String uid, String token) async {
    _lastToken = token;
    try {
      await backend('registerToken', {'token': token});
    } catch (_) {
      // Backend unreachable: at least register it for this account directly.
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'fcmTokens': FieldValue.arrayUnion([token]),
        },
        SetOptions(merge: true),
      );
    }
  }

  /// Call before signing out so this phone stops receiving this account's
  /// alerts.
  Future<void> unregister(String uid) async {
    final token = _lastToken;
    if (token == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmTokens': FieldValue.arrayRemove([token]),
      });
    } catch (_) {
      // Best effort; the backend also reclaims tokens on next sign-in.
    }
  }
}
