import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

class BackendException implements Exception {
  BackendException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Authenticated POST to a backend endpoint; throws [BackendException] with
/// the server's error message on failure.
Future<Map<String, dynamic>> backend(
  String path,
  Map<String, dynamic> body,
) async {
  final token = await FirebaseAuth.instance.currentUser?.getIdToken();
  if (token == null) throw BackendException('not signed in');
  final res = await http.post(
    Uri.parse('$backendBase/$path'),
    headers: {
      'content-type': 'application/json',
      'authorization': 'Bearer $token',
    },
    body: jsonEncode(body),
  );
  final data = res.body.isEmpty
      ? <String, dynamic>{}
      : jsonDecode(res.body) as Map<String, dynamic>;
  if (res.statusCode >= 400) {
    throw BackendException(
      (data['error'] as String?) ?? 'request failed (${res.statusCode})',
    );
  }
  return data;
}
