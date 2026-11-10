import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'push_service.dart';
import 'screens/alert_detail_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// Doc step 14: with a notification payload, Android displays the alert for a
/// backgrounded/terminated app by itself — nothing to do here, but the handler
/// must exist and be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {}

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
            onOpenAlert: (alertId) {
              navigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (_) => AlertDetailScreen(alertId: alertId),
                ),
              );
            },
          );
        }
        return HomeScreen(uid: user.uid);
      },
    );
  }
}

/// Shared helper: resolve an alert (doc steps 19-20).
Future<void> markAlertResolved(String alertId) {
  return FirebaseFirestore.instance.collection('alerts').doc(alertId).update({
    'status': 'resolved',
    'resolvedAt': FieldValue.serverTimestamp(),
    'resolvedBy': FirebaseAuth.instance.currentUser?.uid,
  });
}
