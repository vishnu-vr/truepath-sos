import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show markAlertResolved;

/// Doc steps 16-19: the SOS emergency screen — user/device name, SOS time,
/// location, battery, status, "Open in Maps", "Mark Resolved".
class AlertDetailScreen extends StatelessWidget {
  const AlertDetailScreen({super.key, required this.alertId});

  final String alertId;

  Future<void> _openInMaps(GeoPoint p) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${p.latitude},${p.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final docRef =
        FirebaseFirestore.instance.collection('alerts').doc(alertId);

    return Scaffold(
      appBar: AppBar(title: const Text('SOS alert')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!.data();
          if (data == null) {
            return const Center(child: Text('Alert not found'));
          }

          final active = data['status'] == 'active';
          final uid = FirebaseAuth.instance.currentUser?.uid;
          final isCaregiver =
              ((data['caregiverUids'] as List?) ?? []).contains(uid);
          final location = data['location'] as GeoPoint?;
          final sentAt = (data['sentAt'] as Timestamp?)?.toDate();
          final resolvedAt = (data['resolvedAt'] as Timestamp?)?.toDate();
          final fmt = DateFormat('EEEE d MMM yyyy, h:mm:ss a');

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: active ? scheme.errorContainer : scheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        active ? Icons.sos : Icons.check_circle,
                        size: 64,
                        color: active ? scheme.error : Colors.green,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        active ? 'NEEDS HELP' : 'RESOLVED',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: active ? scheme.error : Colors.green,
                              letterSpacing: 2,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _InfoTile(
                icon: Icons.person,
                label: 'Device / user',
                value: data['deviceName'] ?? data['deviceId'] ?? '—',
              ),
              _InfoTile(
                icon: Icons.schedule,
                label: 'SOS time',
                value: sentAt == null ? '—' : fmt.format(sentAt),
              ),
              _InfoTile(
                icon: Icons.place,
                label: 'Location',
                value: location == null
                    ? '—'
                    : '${location.latitude.toStringAsFixed(5)}, '
                        '${location.longitude.toStringAsFixed(5)}',
              ),
              _InfoTile(
                icon: Icons.battery_std,
                label: 'Battery',
                value: '${data['battery'] ?? '?'}%',
              ),
              if (resolvedAt != null)
                _InfoTile(
                  icon: Icons.task_alt,
                  label: 'Resolved at',
                  value: fmt.format(resolvedAt),
                ),
              const SizedBox(height: 24),
              if (location != null)
                FilledButton.icon(
                  onPressed: () => _openInMaps(location),
                  icon: const Icon(Icons.map),
                  label: const Text('Open in Maps'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              const SizedBox(height: 12),
              if (active && isCaregiver)
                OutlinedButton.icon(
                  onPressed: () async {
                    await markAlertResolved(alertId);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Alert marked resolved')),
                      );
                    }
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Mark Resolved'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label, style: Theme.of(context).textTheme.labelMedium),
      subtitle: Text(value, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
