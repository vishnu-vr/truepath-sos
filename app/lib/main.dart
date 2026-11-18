import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'alarm.dart';
import 'api.dart';
import 'firebase_options.dart';
import 'push_service.dart';
import 'screens/alarm_screen.dart';
import 'screens/alert_detail_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// Doc step 14: SOS pushes are data-only, so when the app is backgrounded or
/// killed this (separate-isolate) handler raises the alarm itself — or
/// silences it when another caregiver responded ("stop" push).
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  await SosAlarm.init();
  await SosAlarm.handleData(message.data);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  runApp(const TruePathCareApp());
}

class TruePathCareApp extends StatelessWidget {
  const TruePathCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TruePath Care',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD32F2F),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _registeredUid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (user == null) {
          _registeredUid = null;
          return const AuthScreen();
        }
        if (_registeredUid != user.uid) {
          _registeredUid = user.uid;
          // Doc steps 13-15: save this phone's FCM token and route
          // notification taps straight to the SOS screen.
          PushService.instance.register(
            uid: user.uid,
            onAlarm: openAlarmScreen,
            onAck: (alertId) async {
              final err = await acknowledgeAlert(alertId);
              openAlertDetail(alertId);
              if (err != null) {
                ScaffoldMessenger.maybeOf(navigatorKey.currentContext!)
                    ?.showSnackBar(SnackBar(content: Text(err)));
              }
            },
          );
        }
        return HomeScreen(uid: user.uid);
      },
    );
  }
}

/// The alarm screen currently shown, so a repeat push/tap doesn't stack it.
String? openAlarmFor;
void setOpenAlarmFor(String? alertId) => openAlarmFor = alertId;

void openAlarmScreen(String alertId) {
  if (openAlarmFor == alertId) return;
  navigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => AlarmScreen(alertId: alertId)),
  );
}

void openAlertDetail(String alertId) {
  navigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => AlertDetailScreen(alertId: alertId)),
  );
}

/// "I'm on it": silence this phone at once, then tell the backend, which
/// records who responded and silences every other caregiver's phone.
/// Returns an error message, or null on success.
Future<String?> acknowledgeAlert(String alertId) async {
  await SosAlarm.stop(alertId);
  if (alertId == SosAlarm.testAlertId) return null;
  try {
    await backend('ack', {'alertId': alertId});
    return null;
  } catch (e) {
    return 'Alarm silenced here, but could not notify the others: $e';
  }
}

/// Shared helper: resolve an alert (doc steps 19-20). Goes through the
/// backend so other caregivers' alarms stop too; falls back to the direct
/// (rules-permitted) Firestore write if the backend is unreachable.
Future<void> markAlertResolved(String alertId) async {
  await SosAlarm.stop(alertId);
  try {
    await backend('ack', {'alertId': alertId, 'action': 'resolve'});
  } on BackendException {
    rethrow;
  } catch (_) {
    await FirebaseFirestore.instance.collection('alerts').doc(alertId).update({
      'status': 'resolved',
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': FirebaseAuth.instance.currentUser?.uid,
    });
  }
}
