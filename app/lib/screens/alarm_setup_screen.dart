import 'package:flutter/material.dart';

import '../alarm.dart';

/// Brands known to kill background apps unless "Autostart" is allowed.
const _aggressiveOems = {
  'xiaomi', 'redmi', 'poco', 'oppo', 'realme', 'vivo', 'iqoo', 'oneplus',
  'huawei', 'honor', 'meizu', 'asus', 'tecno', 'infinix', 'itel',
};

/// Reads the phone's alarm readiness (MainActivity.status) and re-checks
/// whenever the app comes back from a settings page.
mixin _AlarmStatus<T extends StatefulWidget> on State<T>
    implements WidgetsBindingObserver {
  Map<String, dynamic> status = {};

  bool get allRequiredOk =>
      status['notifications'] == true &&
      status['fullScreen'] == true &&
      status['battery'] == true;

  Future<void> refresh() async {
    final s = await SosAlarm.deviceStatus();
    await SosAlarm.ensureChannels(); // picks up newly granted DND access
    if (mounted) setState(() => status = s);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }
}

/// Banner on the Alerts tab, shown only while something required is off.
class AlarmSetupBanner extends StatefulWidget {
  const AlarmSetupBanner({super.key});

  @override
  State<AlarmSetupBanner> createState() => _AlarmSetupBannerState();
}

class _AlarmSetupBannerState extends State<AlarmSetupBanner>
    with WidgetsBindingObserver, _AlarmStatus {
  @override
  Widget build(BuildContext context) {
    if (status.isEmpty || allRequiredOk) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      color: scheme.tertiaryContainer,
      child: ListTile(
        leading: Icon(Icons.alarm_off, color: scheme.onTertiaryContainer),
        title: const Text('SOS alarms may not ring',
            style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text(
            'Finish alarm setup so an SOS can wake this phone.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AlarmSetupScreen()),
        ),
      ),
    );
  }
}

/// Checklist of everything an SOS alarm needs, plus a test alarm.
class AlarmSetupScreen extends StatefulWidget {
  const AlarmSetupScreen({super.key});

  @override
  State<AlarmSetupScreen> createState() => _AlarmSetupScreenState();
}

class _AlarmSetupScreenState extends State<AlarmSetupScreen>
    with WidgetsBindingObserver, _AlarmStatus {
  bool _testPending = false;

  Future<void> _testAlarm() async {
    setState(() => _testPending = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      duration: Duration(seconds: 5),
      content: Text('Test alarm in 10 seconds — lock your phone now to see '
          'the full-screen alarm.'),
    ));
    await Future<void>.delayed(const Duration(seconds: 10));
    await SosAlarm.ring(
      alertId: SosAlarm.testAlertId,
      title: '🧪 TruePath test alarm',
      body: 'This is how an SOS will look and sound. Tap to stop.',
    );
    if (mounted) setState(() => _testPending = false);
  }

  @override
  Widget build(BuildContext context) {
    final manufacturer = '${status['manufacturer'] ?? ''}'.toLowerCase();
    final aggressive = _aggressiveOems.contains(manufacturer);
    return Scaffold(
      appBar: AppBar(title: const Text('SOS alarm setup')),
      body: status.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                  child: Text(
                    'An SOS rings like an alarm clock — full screen, at alarm '
                    'volume, until someone taps "I\'m on it". Android needs a '
                    'few permissions for that.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                _Item(
                  ok: status['notifications'] == true,
                  title: 'Notifications allowed',
                  detail: 'Without this, no alert can be shown at all.',
                  onFix: () => SosAlarm.openSettings('openNotificationSettings'),
                ),
                _Item(
                  ok: status['fullScreen'] == true,
                  title: 'Full-screen alarms',
                  detail: 'Lets an SOS take over the lock screen like an '
                      'incoming call. (Android 14+: "Allow full screen '
                      'notifications".)',
                  onFix: () => SosAlarm.openSettings('openFullScreenSettings'),
                ),
                _Item(
                  ok: status['battery'] == true,
                  title: 'Battery optimisation off',
                  detail: 'Stops Android from delaying SOS pushes to save '
                      'battery. Choose "Allow" / "Unrestricted".',
                  onFix: () => SosAlarm.openSettings('openBatterySettings'),
                ),
                _Item(
                  ok: status['dnd'] == true,
                  optional: true,
                  title: 'Ring in Do Not Disturb (recommended)',
                  detail: 'Lets SOS alarms ring even when Do Not Disturb is '
                      'on. Find "TruePath Care" in the list and allow it.',
                  onFix: () => SosAlarm.openSettings('openDndSettings'),
                ),
                if (aggressive)
                  _Item(
                    ok: null,
                    title: 'Allow Autostart (${status['manufacturer']})',
                    detail: 'This brand stops background apps by default. In '
                        'App info, enable "Autostart" and set battery to "No '
                        'restrictions", or SOS alarms may not arrive while the '
                        'app is closed.',
                    onFix: () => SosAlarm.openSettings('openAppDetails'),
                  ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Also: keep the alarm volume up, and don\'t "Force stop" '
                    'the app — Android blocks all pushes to force-stopped apps '
                    'until they are opened again.',
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _testPending ? null : _testAlarm,
                  icon: const Icon(Icons.alarm),
                  label: Text(_testPending
                      ? 'Test alarm coming… lock your phone'
                      : 'Test the alarm'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.ok,
    required this.title,
    required this.detail,
    required this.onFix,
    this.optional = false,
  });

  /// null = can't be checked automatically (advice only).
  final bool? ok;
  final bool optional;
  final String title;
  final String detail;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final icon = ok == true
        ? const Icon(Icons.check_circle, color: Colors.green)
        : ok == null
            ? const Icon(Icons.info, color: Colors.blueGrey)
            : Icon(optional ? Icons.radio_button_unchecked : Icons.error,
                color: optional ? Colors.amber.shade800 : Colors.red);
    return Card(
      child: ListTile(
        leading: icon,
        title: Text(title),
        subtitle: Text(detail),
        isThreeLine: true,
        trailing: ok == true
            ? null
            : TextButton(onPressed: onFix, child: const Text('Fix')),
      ),
    );
  }
}
