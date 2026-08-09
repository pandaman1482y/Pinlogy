import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app/app_scope.dart';
import '../../models/place.dart';
import '../../services/in_app_route_service.dart';
import '../../widgets/map_tiles.dart';

class RoutePreviewPage extends StatefulWidget {
  const RoutePreviewPage({super.key, required this.place});
  final Place place;
  @override
  State<RoutePreviewPage> createState() => _RoutePreviewPageState();
}

class _RoutePreviewPageState extends State<RoutePreviewPage> {
  final _mapController = MapController();
  InAppRoute? _route;
  LatLng? _origin;
  Object? _error;
  bool _loading = true;
  RouteTravelMode _mode = RouteTravelMode.driving;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = AppScope.read(context);
      final destination = LatLng(
        widget.place.latitude!,
        widget.place.longitude!,
      );
      final origin = (await controller.deviceLocation.locateFast()).point;
      final route = await controller.inAppRoutes.route(
        origin: origin,
        destination: destination,
        mode: _mode,
      );
      if (!mounted) return;
      setState(() {
        _origin = origin;
        _route = route;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(route.points),
            padding: const EdgeInsets.fromLTRB(36, 100, 36, 220),
          ),
        );
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final destination = LatLng(widget.place.latitude!, widget.place.longitude!);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.place.name}への経路')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: destination, initialZoom: 14),
            children: [
              PinlogyMapTiles.buildLayer(),
              if (_route != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _route!.points,
                      strokeWidth: 9,
                      color: Colors.white,
                    ),
                    Polyline(
                      points: _route!.points,
                      strokeWidth: 5,
                      color: const Color(0xFF5367E8),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_origin != null)
                    Marker(
                      point: _origin!,
                      width: 38,
                      height: 38,
                      child: const _RouteMarker(
                        icon: Icons.my_location,
                        color: Color(0xFF5367E8),
                      ),
                    ),
                  Marker(
                    point: destination,
                    width: 42,
                    height: 42,
                    child: const _RouteMarker(
                      icon: Icons.place,
                      color: Color(0xFFE84F77),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_loading)
            const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
          if (_error != null)
            Center(
              child: Card(
                margin: const EdgeInsets.all(28),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.route_outlined, size: 44),
                      const SizedBox(height: 12),
                      const Text(
                        'アプリ内で経路を表示できませんでした',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '通信状況を確認するか、外部ナビをご利用ください。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton(
                            onPressed: _load,
                            child: const Text('再試行'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _openExternal,
                            child: const Text('外部ナビ'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_route != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                child: _RouteSummary(
                  route: _route!,
                  mode: _mode,
                  placeName: widget.place.name,
                  onExternal: _openExternal,
                ),
              ),
            ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: SafeArea(
              child: SegmentedButton<RouteTravelMode>(
                segments: RouteTravelMode.values
                    .map(
                      (mode) => ButtonSegment(
                        value: mode,
                        label: Text(mode.label),
                        icon: Icon(switch (mode) {
                          RouteTravelMode.driving =>
                            Icons.directions_car_outlined,
                          RouteTravelMode.walking => Icons.directions_walk,
                          RouteTravelMode.cycling => Icons.directions_bike,
                        }),
                      ),
                    )
                    .toList(),
                selected: {_mode},
                onSelectionChanged: _loading
                    ? null
                    : (value) {
                        setState(() => _mode = value.first);
                        _load();
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openExternal() async {
    final ok = await AppScope.read(
      context,
    ).directions.openDirections(widget.place);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ナビアプリを開けませんでした')));
    }
  }
}

class _RouteMarker extends StatelessWidget {
  const _RouteMarker({required this.icon, required this.color});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8)],
    ),
    child: Icon(icon, color: Colors.white, size: 21),
  );
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({
    required this.route,
    required this.mode,
    required this.placeName,
    required this.onExternal,
  });
  final InAppRoute route;
  final RouteTravelMode mode;
  final String placeName;
  final VoidCallback onExternal;
  @override
  Widget build(BuildContext context) {
    final km = route.distanceMeters / 1000;
    final minutes = (route.durationSeconds / 60).ceil();
    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              placeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              '${mode.label}で約$minutes分 ・ ${km.toStringAsFixed(km < 10 ? 1 : 0)} km',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5367E8),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onExternal,
                icon: const Icon(Icons.navigation_rounded),
                label: const Text('ナビを開始'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
