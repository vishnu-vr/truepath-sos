import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../alarm.dart';
import '../main.dart'
    show acknowledgeAlert, openAlarmFor, openAlertDetail, setOpenAlarmFor;

/// The full-screen SOS alarm (shown over the lock screen when an alarm
/// launches the app). The ringing itself is the alarm notification; this
/// screen's job is one big "I'm on it" button. As soon as ANY caregiver
/// responds (or it's resolved) it hands over to the normal SOS screen.
class AlarmScreen extends StatefulWidget {
  const AlarmScreen({super.key, required this.alertId});

  final String alertId;

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  bool _busy = false;
  bool _handedOver = false;

  bool get _isTest => widget.alertId == SosAlarm.testAlertId;

  @override
  void initState() {
    super.initState();
    setOpenAlarmFor(widget.alertId);
  }

  @override
  void dispose() {
    _pulse.dispose();
    if (openAlarmFor == widget.alertId) setOpenAlarmFor(null);
    SosAlarm.setAlarmMode(false);
    super.dispose();
  }

  /// Leave the alarm for the SOS details screen (once).
  void _handOver() {
    if (_handedOver || !mounted) return;
    _handedOver = true;
    SosAlarm.stop(widget.alertId);
    Navigator.of(context).pop();
    if (!_isTest) openAlertDetail(widget.alertId);
  }

  Future<void> _ack() async {
    setState(() => _busy = true);
    final err = await acknowledgeAlert(widget.alertId);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
    _handOver();
  }

  Future<void> _openMaps(GeoPoint p) => launchUrl(
        Uri.parse('https://www.google.com/maps/search/?api=1&query='
            '${p.latitude},${p.longitude}'),
        mode: LaunchMode.externalApplication,
      );

  @override
  Widget build(BuildContext context) {
    if (_isTest) {
      return _buildAlarm(
        name: 'Test alarm',
        subtitle: 'This is what an SOS looks and sounds like.',
        location: null,
        battery: null,
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('alerts')
          .doc(widget.alertId)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        if (snap.hasError) {
          // Can't read it (e.g. alert for another account): just show details.
          WidgetsBinding.instance.addPostFrameCallback((_) => _handOver());
        }
        if (data != null &&
            (data['acknowledgedBy'] != null || data['status'] != 'active')) {
          // Someone (maybe us, maybe another caregiver) is on it.
          WidgetsBinding.instance.addPostFrameCallback((_) => _handOver());
        }
        final sentAt = (data?['sentAt'] as Timestamp?)?.toDate();
        return _buildAlarm(
          name: (data?['deviceName'] as String?) ?? 'TruePath cane',
          subtitle: sentAt == null
              ? 'may need help'
              : 'may need help · ${_ago(sentAt)}',
          location: data?['location'] as GeoPoint?,
          battery: data?['battery'],
          simulated: data?['simulated'] == true,
        );
      },
    );
  }

  Widget _buildAlarm({
    required String name,
    required String subtitle,
    required GeoPoint? location,
    required Object? battery,
    bool simulated = false,
  }) {
    const red = Color(0xFFB71C1C);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: red,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  tooltip: 'Back (keeps ringing)',
                  color: Colors.white70,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              const Spacer(),
              ScaleTransition(
                scale: Tween(begin: 0.9, end: 1.1).animate(
                  CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                ),
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.sos, size: 96, color: Colors.white),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                simulated ? 'SOS (TEST)' : 'SOS',
                style: text.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                name,
                textAlign: TextAlign.center,
                style: text.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(color: Colors.white70)),
              if (battery != null) ...[
                const SizedBox(height: 6),
                Text('Cane battery $battery%',
                    style: text.bodyLarge?.copyWith(color: Colors.white70)),
              ],
              const Spacer(),
              if (location != null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openMaps(location),
                    icon: const Icon(Icons.map),
                    label: const Text('Open location in Maps'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 72,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _ack,
                  icon: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 3))
                      : const Icon(Icons.directions_run, size: 30),
                  label: Text(
                    _isTest ? 'Stop test alarm' : "I'M ON IT",
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: red,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(36)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _isTest
                    ? ''
                    : 'Stops the alarm for every caregiver and shows them you are handling it',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    return '${d.inHours} h ago';
  }
}
