import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/radar_event.dart';
import '../models/stream_bounty.dart';
import 'city_map_canvas.dart';
import 'radar_theme.dart';

/// Fully live, real-world map: OpenStreetMap raster tiles with real
/// geolocational markers for active sessions, trials and matches.
///
/// Events carry verified coordinates (lat/lon validated at composition);
/// the camera fits all of them, defaulting to London when nothing is live.
/// If tile servers are unreachable (offline demo, firewall), the widget
/// degrades to the painted city canvas so the Radar never breaks.
class LiveEventMap extends StatefulWidget {
  const LiveEventMap({
    super.key,
    required this.liveEvents,
    required this.scheduledEvents,
    required this.bounties,
    required this.protectedEvents,
    required this.onSelectEvent,
    required this.onSelectBounty,
  });

  final List<RadarEvent> liveEvents;
  final List<RadarEvent> scheduledEvents;
  final List<StreamBounty> bounties;
  final List<RadarEvent> protectedEvents;
  final ValueChanged<RadarEvent> onSelectEvent;
  final ValueChanged<StreamBounty> onSelectBounty;

  @override
  State<LiveEventMap> createState() => _LiveEventMapState();
}

class _LiveEventMapState extends State<LiveEventMap> {
  bool _tileLoadFailed = false;

  List<Marker> _eventMarkers(List<RadarEvent> events, Color color,
      {bool pulse = false}) {
    return [
      for (final e in events)
        if (e.latitude != 0 || e.longitude != 0)
          Marker(
            point: LatLng(e.latitude, e.longitude),
            width: 46,
            height: 46,
            alignment: Alignment.topCenter,
            child: _MapPin(
              color: color,
              icon: pulse ? Icons.play_arrow_rounded : Icons.place,
              glow: pulse,
              onTap: () => widget.onSelectEvent(e),
            ),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final allPoints = [
      for (final e in [
        ...widget.liveEvents,
        ...widget.scheduledEvents,
      ])
        if (e.latitude != 0 || e.longitude != 0) LatLng(e.latitude, e.longitude),
    ];

    final center = allPoints.isNotEmpty
        ? LatLng(
            allPoints.map((p) => p.latitude).reduce((a, b) => a + b) /
                allPoints.length,
            allPoints.map((p) => p.longitude).reduce((a, b) => a + b) /
                allPoints.length,
          )
        : const LatLng(51.5074, -0.1278); // London default.

    if (_tileLoadFailed) {
      // Offline / tiles blocked → painted city canvas fallback.
      return Stack(
        children: [
          const Positioned.fill(child: CityMapCanvas()),
          Positioned.fill(
            child: CityMapMarkerLayout(
              liveEvents: widget.liveEvents,
              scheduledEvents: widget.scheduledEvents,
              bounties: widget.bounties,
              protectedEvents: widget.protectedEvents,
              onSelectEvent: widget.onSelectEvent,
              onSelectBounty: widget.onSelectBounty,
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: allPoints.length > 1 ? 12 : 13,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'dev.radar.app',
              errorTileCallback: (_, _, _) {
                if (!_tileLoadFailed) {
                  setState(() => _tileLoadFailed = true);
                }
              },
            ),
            MarkerLayer(
              markers: [
                ..._eventMarkers(widget.liveEvents, RadarTheme.radar,
                    pulse: true),
                ..._eventMarkers(widget.scheduledEvents, RadarTheme.gold),
                for (final b in widget.bounties)
                  if (b.latitude != null && b.longitude != null)
                    Marker(
                      point: LatLng(b.latitude!, b.longitude!),
                      width: 46,
                      height: 46,
                      child: _MapPin(
                        color: RadarTheme.alert,
                        icon: Icons.gps_fixed,
                        glow: true,
                        onTap: () => widget.onSelectBounty(b),
                      ),
                    ),
                for (final e in widget.protectedEvents)
                  if (e.latitude != 0 || e.longitude != 0)
                    Marker(
                      point: LatLng(e.latitude, e.longitude),
                      width: 40,
                      height: 40,
                      child: const _MapPin(
                        color: Color(0xFF4A90D9),
                        icon: Icons.shield,
                      ),
                    ),
              ],
            ),
          ],
        ),
        const Positioned(
          bottom: 8,
          right: 10,
          child: Text(
            '© OpenStreetMap contributors',
            style: TextStyle(fontSize: 9, color: RadarTheme.textDim),
          ),
        ),
      ],
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({
    required this.color,
    required this.icon,
    this.glow = false,
    this.onTap,
  });

  final Color color;
  final IconData icon;
  final bool glow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: glow
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.55),
                    blurRadius: 14,
                    spreadRadius: 3,
                  ),
                ]
              : null,
        ),
        child: CircleAvatar(
          radius: 15,
          backgroundColor: color,
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}
