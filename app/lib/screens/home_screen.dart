import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'alert_detail_screen.dart';
import 'cane_screen.dart';
import 'claim_screen.dart';

/// Home: Alerts tab (doc steps 16 + 20) and My canes tab (claiming +
/// caregiver management).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('TruePath Care'),
          actions: [
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () => FirebaseAuth.instance.signOut(),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.sos), text: 'Alerts'),
            Tab(icon: Icon(Icons.assist_walker), text: 'My canes'),
          ]),
        ),
        body: TabBarView(children: [
          _AlertsTab(uid: uid),
          _CanesTab(uid: uid),
        ]),
        floatingActionButton: Builder(
          builder: (context) => FloatingActionButton.extended(
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Add cane'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ClaimScreen()),
            ),
          ),
        ),
      ),
    );
  }
}

/* ----------------------------------------------------------- Alerts tab */

class _AlertsTab extends StatelessWidget {
  const _AlertsTab({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('alerts')
        .where('memberUids', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .limit(100);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No alerts.\nWhen a TruePath cane sends an SOS it will appear here.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final active = docs.where((d) => d.data()['status'] == 'active').toList();
        final resolved = docs.where((d) => d.data()['status'] != 'active').toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: [
            if (active.isNotEmpty) ...[
              SectionHeader('ACTIVE EMERGENCIES',
                  color: Theme.of(context).colorScheme.error),
              ...active.map((d) => _AlertCard(doc: d, active: true)),
              const SizedBox(height: 16),
            ],
            if (resolved.isNotEmpty) ...[
              const SectionHeader('HISTORY'),
              ...resolved.map((d) => _AlertCard(doc: d, active: false)),
            ],
          ],
        );
      },
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.doc, required this.active});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final scheme = Theme.of(context).colorScheme;
    final sentAt = (data['sentAt'] as Timestamp?)?.toDate();
    final when = sentAt == null ? '—' : DateFormat('d MMM, h:mm a').format(sentAt);

    return Card(
      color: active ? scheme.errorContainer : null,
      child: ListTile(
        leading: Icon(
          active ? Icons.sos : Icons.check_circle_outline,
          color: active ? scheme.error : scheme.outline,
          size: 32,
        ),
        title: Text(
          data['deviceName'] ?? data['deviceId'] ?? 'Unknown device',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('$when · battery ${data['battery'] ?? '?'}%'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AlertDetailScreen(alertId: doc.id)),
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------ Canes tab */

class _CanesTab extends StatelessWidget {
  const _CanesTab({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final caring = db.collection('devices').where('caregiverUids', arrayContains: uid);
    final mine = db.collection('devices').where('caneUserUid', isEqualTo: uid);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
      children: [
        _CaneSection(title: 'CANES I CARE FOR', query: caring, uid: uid),
        _CaneSection(title: 'MY CANE', query: mine, uid: uid, excludeCaregiverUid: uid),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Unboxed a new cane?\nTap "Add cane" and scan or enter its claim code.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      ],
    );
  }
}

class _CaneSection extends StatelessWidget {
  const _CaneSection({
    required this.title,
    required this.query,
    required this.uid,
    this.excludeCaregiverUid,
  });

  final String title;
  final Query<Map<String, dynamic>> query;
  final String uid;

  /// For "My cane": skip canes already shown under "caring for".
  final String? excludeCaregiverUid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Text('Error: ${snapshot.error}'),
          );
        }
        var docs = snapshot.data?.docs ?? [];
        if (excludeCaregiverUid != null) {
          docs = docs
              .where((d) => !((d.data()['caregiverUids'] as List?) ?? [])
                  .contains(excludeCaregiverUid))
              .toList();
        }
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title),
            ...docs.map((d) {
              final data = d.data();
              final battery = data['battery'];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.assist_walker, size: 32),
                  title: Text(
                    data['name'] ?? d.id,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${d.id} · ${data['status'] ?? '?'}'
                    '${battery != null ? ' · battery $battery%' : ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CaneScreen(deviceId: d.id)),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color ?? Theme.of(context).colorScheme.outline,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}
