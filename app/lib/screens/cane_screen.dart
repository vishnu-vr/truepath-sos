import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';

/// One cane: status, battery, people. The owner and the primary caregiver
/// can add/remove caregivers, transfer primary, link the cane user's
/// account, and rename the cane.
class CaneScreen extends StatelessWidget {
  const CaneScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final docRef = FirebaseFirestore.instance.collection('devices').doc(deviceId);

    return Scaffold(
      appBar: AppBar(title: Text(deviceId)),
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
          if (data == null) return const Center(child: Text('Cane not found'));

          final canManage =
              data['ownerUid'] == uid || data['primaryCaregiverUid'] == uid;
          final members = (data['members'] as Map<String, dynamic>?) ?? {};
          final caregiverUids = List<String>.from(data['caregiverUids'] ?? []);
          final lastSeen = (data['lastSeenAt'] as Timestamp?)?.toDate();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.assist_walker, size: 40),
                  title: Row(children: [
                    Expanded(
                      child: Text(
                        data['name'] ?? deviceId,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ),
                    if (canManage)
                      IconButton(
                        tooltip: 'Rename',
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _rename(context, data['name'] ?? ''),
                      ),
                  ]),
                  subtitle: Text(
                    'Status: ${data['status'] ?? '?'}'
                    '${data['battery'] != null ? ' · battery ${data['battery']}%' : ''}'
                    '${lastSeen != null ? '\nLast seen ${DateFormat('d MMM, h:mm a').format(lastSeen)}' : ''}',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('PEOPLE',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                        letterSpacing: 1.2,
                      )),
              const SizedBox(height: 4),
              ...caregiverUids.map((cUid) => _PersonTile(
                    uid: cUid,
                    info: members[cUid] as Map<String, dynamic>?,
                    isOwner: cUid == data['ownerUid'],
                    isPrimary: cUid == data['primaryCaregiverUid'],
                    isCaneUser: cUid == data['caneUserUid'],
                    manageable: canManage,
                    onAction: (action) => _run(context, {
                      'deviceId': deviceId,
                      'action': action,
                      'uid': cUid,
                    }),
                  )),
              if (data['caneUserUid'] != null &&
                  !caregiverUids.contains(data['caneUserUid']))
                _PersonTile(
                  uid: data['caneUserUid'],
                  info: members[data['caneUserUid']] as Map<String, dynamic>?,
                  isOwner: data['caneUserUid'] == data['ownerUid'],
                  isPrimary: false,
                  isCaneUser: true,
                  manageable: false,
                  onAction: (_) {},
                ),
              if (canManage) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add caregiver'),
                  onPressed: () => _byEmail(context, 'Add caregiver',
                      'Their TruePath account email', 'addCaregiver'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.accessibility_new),
                  label: Text(data['caneUserUid'] == null
                      ? 'Link cane user account'
                      : 'Change cane user account'),
                  onPressed: () => _byEmail(context, 'Link cane user',
                      "The cane user's account email", 'linkCaneUser'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _run(BuildContext context, Map<String, dynamic> body) async {
    try {
      await backend('manage', body);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _byEmail(
      BuildContext context, String title, String hint, String action) async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
    if (email != null && email.isNotEmpty && context.mounted) {
      await _run(context, {'deviceId': deviceId, 'action': action, 'email': email});
    }
  }

  Future<void> _rename(BuildContext context, String current) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename cane'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      await _run(context, {'deviceId': deviceId, 'action': 'setName', 'name': name});
    }
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.uid,
    required this.info,
    required this.isOwner,
    required this.isPrimary,
    required this.isCaneUser,
    required this.manageable,
    required this.onAction,
  });

  final String uid;
  final Map<String, dynamic>? info;
  final bool isOwner;
  final bool isPrimary;
  final bool isCaneUser;
  final bool manageable;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badges = <Widget>[
      if (isOwner) _badge(context, 'Owner', scheme.primary),
      if (isPrimary) _badge(context, 'Primary', scheme.tertiary),
      if (isCaneUser) _badge(context, 'Cane user', scheme.secondary),
    ];
    return Card(
      child: ListTile(
        leading: const Icon(Icons.person),
        title: Text(info?['name'] ?? uid,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(info?['email'] ?? ''),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...badges,
            if (manageable && !isOwner)
              PopupMenuButton<String>(
                onSelected: onAction,
                itemBuilder: (_) => [
                  if (!isPrimary)
                    const PopupMenuItem(
                        value: 'setPrimaryCaregiver',
                        child: Text('Make primary caregiver')),
                  const PopupMenuItem(
                      value: 'removeCaregiver', child: Text('Remove')),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
