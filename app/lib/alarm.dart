import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The SOS alarm: a full-screen, looping, alarm-volume notification raised by
/// the app itself from a data-only FCM push (see `fireAlert` in the backend).
///
/// Everything here must work from the FCM background isolate too (no
/// Firebase, no navigator) — it only touches the local notifications plugin.
class SosAlarm {
  SosAlarm._();

  /// Alarm channels. Android freezes a channel's sound/DND settings when it
  /// is created, so the DND-bypassing variant is a separate channel created
  /// only once the user has granted Do Not Disturb access.
  static const alarmChannelId = 'sos_alarm';
  static const alarmDndChannelId = 'sos_alarm_dnd';

  /// Plain high-priority channel: stale SOS pushes (phone was offline) and
  /// "handled by …" updates. Kept from the first app version.
  static const infoChannelId = 'sos_alerts';

  /// Test alarm from the setup screen (no backend involved).
  static const testAlertId = '__test__';

  /// Pushes older than this ring as a normal notification, not an alarm.
  static const staleAfter = Duration(minutes: 30);

  static const _alarmSound =
      UriAndroidNotificationSound('content://settings/system/alarm_alert');
  static final _vibration =
      Int64List.fromList([0, 1000, 500, 1000, 500, 1000, 1500]);
  static const _flagInsistent = 4; // Notification.FLAG_INSISTENT: loop sound

  static final plugin = FlutterLocalNotificationsPlugin();
  static const native = MethodChannel('truepath/alarm');

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Stable notification id per alert (String.hashCode is not guaranteed
  /// stable across isolates/runs): FNV-1a, 31-bit.
  static int idFor(String alertId) {
    var h = 0x811c9dc5;
    for (final c in alertId.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h & 0x7fffffff;
  }

  static Future<bool> hasDndAccess() async =>
      (await _android?.hasNotificationPolicyAccess()) ?? false;

  /// Creates the channels (idempotent). Safe to call often.
  static Future<void> ensureChannels() async {
    final android = _android;
    if (android == null) return;
    await android.createNotificationChannel(AndroidNotificationChannel(
      alarmChannelId,
      'SOS alarm',
      description: 'Rings like an alarm until someone responds to an SOS',
      importance: Importance.max,
      sound: _alarmSound,
      vibrationPattern: _vibration,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    ));
    if (await hasDndAccess()) {
      await android.createNotificationChannel(AndroidNotificationChannel(
        alarmDndChannelId,
        'SOS alarm (overrides Do Not Disturb)',
        description: 'SOS alarm that also rings in Do Not Disturb',
        importance: Importance.max,
        bypassDnd: true,
        sound: _alarmSound,
        vibrationPattern: _vibration,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ));
    }
    await android.createNotificationChannel(const AndroidNotificationChannel(
      infoChannelId,
      'SOS updates',
      description: 'Who is handling an SOS, and SOS alerts received late',
      importance: Importance.high,
    ));
  }

  /// Initializes the plugin in the current isolate (callbacks only matter in
  /// the UI isolate).
  static Future<void> init({
    void Function(NotificationResponse response)? onResponse,
  }) async {
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: onResponse,
    );
    await ensureChannels();
  }

  /// Handles a TruePath data push. Returns the alertId of a new SOS, if any.
  static Future<String?> handleData(Map<String, dynamic> data) async {
    final kind = data['kind'];
    final alertId = data['alertId'] as String?;
    if (alertId == null || alertId.isEmpty) return null;
    if (kind == 'sos') {
      await ring(
        alertId: alertId,
        title: (data['title'] as String?) ?? '🆘 TruePath SOS',
        body: (data['body'] as String?) ?? 'A TruePath cane may need help',
        sentAtMs: int.tryParse('${data['sentAtMs']}'),
      );
      return alertId;
    }
    if (kind == 'stop') {
      await stop(
        alertId,
        byName: data['byName'] as String?,
        resolved: data['reason'] == 'resolved',
      );
    }
    return null;
  }

  /// Raises the alarm for an alert.
  static Future<void> ring({
    required String alertId,
    required String title,
    required String body,
    int? sentAtMs,
  }) async {
    await ensureChannels();
    final stale = sentAtMs != null &&
        DateTime.now().millisecondsSinceEpoch - sentAtMs >
            staleAfter.inMilliseconds;
    if (stale) {
      // Arrived long after the fact (phone offline): no alarm, just inform.
      await plugin.show(
        id: idFor(alertId),
        title: title,
        body: 'Received late — $body',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(infoChannelId, 'SOS updates',
              importance: Importance.high,
              priority: Priority.high,
              groupKey: 'truepath.sos.$alertId'),
        ),
        payload: alertId,
      );
      return;
    }
    final dnd = await hasDndAccess();
    await plugin.show(
      id: idFor(alertId),
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          dnd ? alarmDndChannelId : alarmChannelId,
          'SOS alarm',
          importance: Importance.max,
          priority: Priority.max,
          channelBypassDnd: dnd,
          category: AndroidNotificationCategory.alarm,
          // Own explicit group per alert: Android auto-groups an app's
          // ungrouped notifications once there are several, and auto-grouped
          // children are SILENCED (and lose their full-screen launch).
          groupKey: 'truepath.sos.$alertId',
          fullScreenIntent: true, // lock screen → straight into the alarm
          visibility: NotificationVisibility.public,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          sound: _alarmSound,
          vibrationPattern: _vibration,
          additionalFlags: Int32List.fromList([_flagInsistent]),
          ongoing: true, // can't be swiped away
          autoCancel: false, // tapping it doesn't silence it
          timeoutAfter: const Duration(minutes: 15).inMilliseconds,
          color: const Color(0xFFD32F2F),
          colorized: true,
          actions: const [
            AndroidNotificationAction(
              'ack',
              "I'm on it",
              showsUserInterface: true,
            ),
          ],
        ),
      ),
      payload: alertId,
    );
  }

  /// Silences the alarm for [alertId]; with [byName], leaves a quiet
  /// "handled by …" note in its place.
  static Future<void> stop(String alertId,
      {String? byName, bool resolved = false}) async {
    final id = idFor(alertId);
    await plugin.cancel(id: id);
    if (byName == null || byName.isEmpty) return;
    await plugin.show(
      id: id,
      title: resolved ? '✅ SOS resolved' : '✅ SOS being handled',
      body: resolved
          ? 'Resolved by $byName'
          : '$byName acknowledged the SOS and is on it',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(infoChannelId, 'SOS updates',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            groupKey: 'truepath.sos.$alertId',
            onlyAlertOnce: true),
      ),
      payload: alertId,
    );
  }

  /// Lock-screen display is enabled natively only when an alarm launched the
  /// app; turn it off again when the alarm screen closes.
  static Future<void> setAlarmMode(bool on) async {
    try {
      await native.invokeMethod('setAlarmMode', on);
    } catch (_) {}
  }

  /// Device readiness for alarms (see MainActivity.status).
  static Future<Map<String, dynamic>> deviceStatus() async {
    try {
      final m = await native.invokeMapMethod<String, dynamic>('status');
      return m ?? {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> openSettings(String which) async {
    try {
      await native.invokeMethod(which);
    } catch (_) {}
  }
}
