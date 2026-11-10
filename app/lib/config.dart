import 'package:flutter/foundation.dart';

/// Backend base URL.
/// - Release builds (App Distribution / real phones): deployed Cloud Functions.
/// - Debug builds (development): the local functions emulator — 10.0.2.2
///   reaches the host Mac from inside the Android emulator.
const _prod = 'https://us-central1-truepath-sos-2611.cloudfunctions.net';
const _local = 'http://10.0.2.2:15002/truepath-sos-2611/us-central1';

const backendBase = kReleaseMode ? _prod : _local;
