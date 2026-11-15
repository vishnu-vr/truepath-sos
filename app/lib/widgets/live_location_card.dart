import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// Live position (map + 24h trail) and live battery for one cane.
/// [device] is the latest device doc data, streamed by the parent screen.
class LiveLocationCard extends StatefulWidget {
  const LiveLocationCard({super.key, required this.deviceId, required this.device});

  final String deviceId;
  final Map<String, dynamic> device;

  @override
  State<LiveLocationCard> createState() => _LiveLocationCardState();
}

class _LiveLocationCardState extends State<LiveLocationCard> {
  final _map = MapController();
  bool _mapReady = false;
  LatLng? _lastCentered;

  static const _trailHours = 24;

  Stream<QuerySnapshot<Map<String, dynamic>>> get _trail => FirebaseFirestore.instance
      .collection('devices')
      .doc(widget.deviceId)
      .collection('locations')
      .where('at',
          isGreaterThan: Timestamp.fromDate(
              DateTime.now().subtract(const Duration(hours: _trailHours))))
      .orderBy('at')
      .snapshots();

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _trailStream = _trail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final geo = widget.device['lastLocation'] as GeoPoint?;
    final locAt = (widget.device['lastLocationAt'] as Timestamp?)?.toDate();
    final battery = widget.device['battery'] as num?;
    final batteryAt = (widget.device['batteryAt'] as Timestamp?)?.toDate() ??
        (widget.device['lastSeenAt'] as Timestamp?)?.toDate();
    final current = geo == null ? null : LatLng(geo.latitude, geo.longitude);

    // Follow the cane: recenter whenever a new position arrives.
    if (current != null && _mapReady && current != _lastCentered) {
      _lastCentered = current;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _map.move(current, _map.camera.zoom);
      });
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 260,
            child: current == null
                ? Container(
                    color: scheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: const Text('No location reported yet'),
                  )
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _trailStream,
                    builder: (context, snap) {
                      final trail = (snap.data?.docs ?? [])
                          .map((d) => d.data()['location'] as GeoPoint?)
                          .whereType<GeoPoint>()
                          .map((g) => LatLng(g.latitude, g.longitude))
                          .toList();
                      return FlutterMap(
                        mapController: _map,
                        options: MapOptions(
                          initialCenter: current,
                          initialZoom: 16,
                          onMapReady: () {
                            _mapReady = true;
                            _lastCentered = current;
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'app.truepath.truepath_care',
                          ),
                          if (trail.length > 1)
                            PolylineLayer(polylines: [
                              Polyline(
                                points: trail,
                                strokeWidth: 4,
                                color: scheme.primary.withValues(alpha: 0.6),
                              ),
                            ]),
                          MarkerLayer(markers: [
                            Marker(
                              point: current,
                              width: 44,
                              height: 44,
                              child: Icon(Icons.location_on, size: 44, color: scheme.error),
                            ),
                          ]),
                          const SimpleAttributionWidget(
                            source: Text('OpenStreetMap contributors'),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                _BatteryBadge(battery: battery),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        battery == null ? 'Battery unknown' : 'Battery ${battery.round()}%',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        [
                          if (locAt != null) 'Location ${_ago(locAt)}',
                          if (locAt == null && batteryAt != null) 'Updated ${_ago(batteryAt)}',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (current != null)
                  TextButton.icon(
                    icon: const Icon(Icons.map, size: 18),
                    label: const Text('Open in Maps'),
                    onPressed: () => launchUrl(
                      Uri.parse('https://www.google.com/maps/search/?api=1'
                          '&query=${current.latitude},${current.longitude}'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BatteryBadge extends StatelessWidget {
  const _BatteryBadge({required this.battery});
  final num? battery;

  @override
  Widget build(BuildContext context) {
    final b = battery;
    final color = b == null
        ? Theme.of(context).colorScheme.outline
        : b < 20
            ? Colors.red.shade700
            : b < 50
                ? Colors.amber.shade800
                : Colors.green.shade700;
    final icon = b == null
        ? Icons.battery_unknown
        : b < 20
            ? Icons.battery_alert
            : b < 50
                ? Icons.battery_3_bar
                : b < 90
                    ? Icons.battery_5_bar
                    : Icons.battery_full;
    return Icon(icon, color: color, size: 32);
  }
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}
