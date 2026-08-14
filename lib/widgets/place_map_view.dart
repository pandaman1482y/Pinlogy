import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_scope.dart';
import '../controllers/pinlogy_map_interaction_controller.dart';
import '../features/places/place_details_sheet.dart';
import '../models/models.dart';
import '../services/map_cluster_service.dart';
import '../services/source_link_service.dart';
import 'map_tiles.dart';
import 'place_photo.dart';

/// 日本語地名・店舗表記つきの地図ビュー。
class PlaceMapView extends StatefulWidget {
  const PlaceMapView({
    super.key,
    required this.places,
    required this.mapController,
    required this.mapId,
    this.onLongPress,
    this.onMyLocation,
    this.searchField,
    this.initialCenter,
    this.initialZoom,
    this.userLocation,
    this.locating = false,
    this.focusPlaceId,
    this.routePolylines = const [],
    this.markerLabels = const {},
    this.clusterMarkers = true,
    this.onSearchArea,
  });

  final List<Place> places;
  final MapController mapController;
  final String mapId;
  final void Function(LatLng point)? onLongPress;
  final VoidCallback? onMyLocation;
  final Widget? searchField;
  final LatLng? initialCenter;
  final double? initialZoom;
  final LatLng? userLocation;
  final bool locating;
  final String? focusPlaceId;
  final List<Polyline> routePolylines;
  final Map<String, String> markerLabels;
  final bool clusterMarkers;
  final ValueChanged<MapCamera>? onSearchArea;

  static const japanOverview = LatLng(36.4, 138.0);
  static const focusZoom = 16.5;
  static const minZoom = 3.0;
  static const maxZoom = 19.0;

  static LatLng pointFor(Place place, {int index = 0}) {
    if (place.latitude != null && place.longitude != null) {
      return LatLng(place.latitude!, place.longitude!);
    }
    if (place.mapPinX != null && place.mapPinY != null) {
      return LatLng(
        30.0 + place.mapPinY! * 14.0,
        128.0 + place.mapPinX! * 18.0,
      );
    }
    return LatLng(35.0 + (index % 5) * 0.08, 135.5 + (index % 4) * 0.08);
  }

  static LatLng centerFor(List<Place> places) {
    if (places.isEmpty) return japanOverview;
    var lat = 0.0;
    var lng = 0.0;
    for (var i = 0; i < places.length; i++) {
      final point = pointFor(places[i], index: i);
      lat += point.latitude;
      lng += point.longitude;
    }
    return LatLng(lat / places.length, lng / places.length);
  }

  static double zoomFor(List<Place> places) {
    if (places.isEmpty) return 6.2;
    if (places.length == 1) return 16;
    return 13.5;
  }

  @override
  State<PlaceMapView> createState() => _PlaceMapViewState();
}

class _PlaceMapViewState extends State<PlaceMapView> {
  static const _stylePreferenceKey = 'pinlogy_map_tile_style_v2';

  /// 既定は施設表示を残した、明るく柔らかいVoyagerスタイル。
  MapTileStyle _style = MapTileStyle.stores;
  late final PinlogyMapInteractionController _interaction;
  final StreamController<void> _tileReset = StreamController.broadcast();
  Timer? _loadingTimer;
  Timer? _cameraSaveTimer;
  Timer? _cameraIdleTimer;
  MapCamera? _latestCamera;
  bool _cameraMovedByGesture = false;
  bool _cameraReady = false;
  final PageController _placePageController = PageController(
    viewportFraction: .9,
  );

  @override
  void initState() {
    super.initState();
    _interaction = PinlogyMapInteractionController(
      initialZoom: widget.initialZoom ?? PlaceMapView.zoomFor(widget.places),
    );
    unawaited(_restoreStyle());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showMapLoading();
      final center =
          widget.initialCenter ?? PlaceMapView.centerFor(widget.places);
      unawaited(
        PinlogyMapTiles.preloadAround(
          context,
          latitude: center.latitude,
          longitude: center.longitude,
          zoom: _interaction.settledZoom.value,
          style: _style,
        ),
      );
      unawaited(_restoreCamera());
    });
  }

  @override
  void didUpdateWidget(covariant PlaceMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _interaction.selectedPlaceId.value;
    if (selected != null &&
        !widget.places.any((place) => place.id == selected)) {
      _interaction.selectPlace(null);
    }
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    _cameraSaveTimer?.cancel();
    _cameraIdleTimer?.cancel();
    _interaction.dispose();
    _placePageController.dispose();
    _tileReset.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final places = widget.places;
    final center = widget.initialCenter ?? PlaceMapView.centerFor(places);
    final zoom = widget.initialZoom ?? PlaceMapView.zoomFor(places);
    final initialFit =
        widget.initialCenter == null &&
            widget.initialZoom == null &&
            places.length > 1
        ? _fitFor(places)
        : null;
    final stores = _style == MapTileStyle.stores;
    final controller = AppScope.of(context);

    return Stack(
      children: [
        ColoredBox(
          color: PinlogyMapTiles.mapBackground,
          child: FlutterMap(
            mapController: widget.mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: zoom,
              initialCameraFit: initialFit,
              minZoom: PlaceMapView.minZoom,
              maxZoom: PlaceMapView.maxZoom,
              backgroundColor: PinlogyMapTiles.mapBackground,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              onPositionChanged: (camera, hasGesture) {
                _latestCamera = camera;
                if (hasGesture) {
                  if (!_cameraMovedByGesture) _showMapLoading();
                  _cameraMovedByGesture = true;
                }
                _scheduleCameraIdle();
              },
              onLongPress: widget.onLongPress == null
                  ? null
                  : (tapPosition, point) => widget.onLongPress!(point),
            ),
            children: [
              PinlogyMapTiles.buildLayer(
                style: _style,
                reset: _tileReset.stream,
                onError: (_, _, _) {
                  if (!mounted) return;
                  _interaction.tileErrors.value++;
                  _interaction.mapLoading.value = false;
                },
              ),
              if (widget.routePolylines.isNotEmpty)
                PolylineLayer(polylines: widget.routePolylines),
              ValueListenableBuilder<double>(
                valueListenable: _interaction.settledZoom,
                builder: (context, settledZoom, _) {
                  final markerGroups = widget.clusterMarkers
                      ? clusterMapPlaces(
                          places,
                          settledZoom,
                          pointFor: (place, index) =>
                              PlaceMapView.pointFor(place, index: index),
                        )
                      : [
                          for (var i = 0; i < places.length; i++)
                            MapMarkerGroup(
                              places: [places[i]],
                              center: PlaceMapView.pointFor(
                                places[i],
                                index: i,
                              ),
                            ),
                        ];
                  return ValueListenableBuilder<String?>(
                    valueListenable: _interaction.selectedPlaceId,
                    builder: (context, selectedPlaceId, _) => MarkerLayer(
                      markers: [
                        if (widget.userLocation != null)
                          Marker(
                            point: widget.userLocation!,
                            width: 28,
                            height: 28,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF007AFF),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF007AFF,
                                    ).withValues(alpha: 0.4),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        for (final group in markerGroups)
                          if (group.places.length > 1)
                            Marker(
                              point: group.center,
                              width: 58,
                              height: 58,
                              child: _PlaceCluster(
                                count: group.places.length,
                                onTap: () {
                                  _interaction.selectPlace(null);
                                  widget.mapController.move(
                                    group.center,
                                    (settledZoom + 2).clamp(
                                      PlaceMapView.minZoom,
                                      PlaceMapView.maxZoom,
                                    ),
                                  );
                                },
                              ),
                            )
                          else
                            Marker(
                              point: group.center,
                              width: settledZoom >= 17 ? 132 : 72,
                              height: settledZoom >= 17 ? 104 : 82,
                              alignment: Alignment.topCenter,
                              child: _AppleStylePin(
                                place: group.places.first,
                                imagePath:
                                    group.places.first.coverImagePath ??
                                    controller
                                        .primarySourceForPlace(
                                          group.places.first.id,
                                        )
                                        ?.imagePaths
                                        .firstOrNull,
                                visited: group.places.first.isVisited,
                                focused:
                                    group.places.first.id ==
                                        widget.focusPlaceId ||
                                    group.places.first.id == selectedPlaceId,
                                markerLabel:
                                    widget.markerLabels[group.places.first.id],
                                showName: settledZoom >= 17,
                                onTap: () {
                                  _selectPlace(group.places.first, places);
                                },
                              ),
                            ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        if (widget.searchField != null)
          Positioned(
            top: 22,
            left: 20,
            right: 20,
            child: Material(
              elevation: 0,
              shadowColor: Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              color: Colors.white.withValues(alpha: 0.96),
              child: widget.searchField,
            ),
          ),
        ValueListenableBuilder<bool>(
          valueListenable: _interaction.mapLoading,
          builder: (context, loading, _) => loading
              ? Positioned(
                  top: widget.searchField != null ? 138 : 18,
                  left: 0,
                  right: 0,
                  child: const Center(
                    child: _MapStatusChip(
                      icon: Icons.downloading_rounded,
                      label: '地図を読み込み中…',
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        ValueListenableBuilder<int>(
          valueListenable: _interaction.tileErrors,
          builder: (context, errors, _) => errors >= 3
              ? Positioned(
                  top: widget.searchField != null ? 138 : 18,
                  left: 20,
                  right: 20,
                  child: _MapRetryCard(onRetry: _retryTiles),
                )
              : const SizedBox.shrink(),
        ),
        if (widget.onSearchArea != null)
          ValueListenableBuilder<bool>(
            valueListenable: _interaction.areaSearchAvailable,
            builder: (context, available, _) => available
                ? Positioned(
                    top: widget.searchField != null ? 138 : 18,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: FilledButton.tonalIcon(
                        onPressed: _searchCurrentArea,
                        icon: const Icon(Icons.search_rounded, size: 18),
                        label: const Text('このエリアを検索'),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ValueListenableBuilder<String?>(
          valueListenable: _interaction.selectedPlaceId,
          builder: (context, selectedPlaceId, _) {
            if (selectedPlaceId == null || places.isEmpty) {
              return const SizedBox.shrink();
            }
            return Positioned(
              left: 0,
              right: 0,
              bottom: 92,
              height: 112,
              child: PageView.builder(
                controller: _placePageController,
                itemCount: places.length,
                onPageChanged: (index) {
                  final place = places[index];
                  _interaction.selectPlace(place.id);
                  widget.mapController.move(
                    PlaceMapView.pointFor(place, index: index),
                    widget.mapController.camera.zoom,
                  );
                },
                itemBuilder: (context, index) {
                  final place = places[index];
                  final source = controller.primarySourceForPlace(place.id);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: _SelectedPlaceCard(
                      place: place,
                      positionLabel: '${index + 1}/${places.length}',
                      imagePath:
                          place.coverImagePath ??
                          source?.imagePaths.firstOrNull,
                      source: source,
                      onClose: () => _interaction.selectPlace(null),
                      onOpen: () => showPlaceDetails(context, place),
                      onDirections: () async {
                        final opened = await controller.directions
                            .openDirections(place);
                        if (!context.mounted || opened) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('経路を開けませんでした')),
                        );
                      },
                      onRefreshSource: source?.url == null
                          ? null
                          : () async {
                              final refreshed = await controller.shareReceiver
                                  .refreshOfficialPreview(source!, force: true);
                              return refreshed.imagePaths.firstOrNull;
                            },
                    ),
                  );
                },
              ),
            );
          },
        ),
        ValueListenableBuilder<String?>(
          valueListenable: _interaction.selectedPlaceId,
          builder: (context, selectedPlaceId, _) => Positioned(
            left: 16,
            bottom: selectedPlaceId == null ? 100 : 210,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '長押しでピンを追加',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                PinlogyMapTiles.attributionBadge(_style),
              ],
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 92,
          top: widget.searchField != null ? 90 : 24,
          child: Align(
            alignment: Alignment.bottomRight,
            child: SingleChildScrollView(
              reverse: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (places.isNotEmpty) ...[
                    _SoftFab(
                      heroTag: 'fit-all-places',
                      icon: Icons.center_focus_strong_rounded,
                      tooltip: 'すべてのピンを表示',
                      onPressed: _fitAllPlaces,
                    ),
                    const SizedBox(height: 10),
                  ],
                  _SoftFab(
                    heroTag: 'map-style',
                    icon: stores ? Icons.layers_outlined : Icons.map_outlined,
                    tooltip: '地図の種類を選ぶ',
                    onPressed: _showMapStylePicker,
                  ),
                  if (widget.onMyLocation != null) ...[
                    const SizedBox(height: 10),
                    _SoftFab(
                      heroTag: 'location',
                      icon: Icons.my_location_rounded,
                      onPressed: widget.locating ? null : widget.onMyLocation,
                      loading: widget.locating,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showMapLoading() {
    _loadingTimer?.cancel();
    _interaction.mapLoading.value = true;
    _loadingTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted && _interaction.tileErrors.value < 3) {
        _interaction.mapLoading.value = false;
      }
    });
  }

  Future<void> _restoreStyle() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_stylePreferenceKey);
    final restored = MapTileStyle.values
        .where((style) => style.name == saved)
        .firstOrNull;
    if (!mounted || restored == null || restored == _style) return;
    setState(() => _style = restored);
  }

  Future<void> _showMapStylePicker() async {
    final selected = await showModalBottomSheet<MapTileStyle>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Text(
                  '地図の種類',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              for (final style in MapTileStyle.values)
                ListTile(
                  leading: Icon(
                    style == MapTileStyle.stores
                        ? Icons.layers_outlined
                        : Icons.map_outlined,
                  ),
                  title: Text(style.label),
                  subtitle: Text(style.description),
                  trailing: style == _style
                      ? const Icon(Icons.check_circle_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, style),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null || selected == _style) return;
    _showMapLoading();
    setState(() => _style = selected);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_stylePreferenceKey, selected.name);
    if (!mounted) return;
    final camera = widget.mapController.camera;
    unawaited(
      PinlogyMapTiles.preloadAround(
        context,
        latitude: camera.center.latitude,
        longitude: camera.center.longitude,
        zoom: camera.zoom,
        style: selected,
      ),
    );
  }

  void _retryTiles() {
    _interaction.tileErrors.value = 0;
    _interaction.mapLoading.value = true;
    _tileReset.add(null);
    final camera = widget.mapController.camera;
    unawaited(
      PinlogyMapTiles.preloadAround(
        context,
        latitude: camera.center.latitude,
        longitude: camera.center.longitude,
        zoom: camera.zoom,
        style: _style,
      ),
    );
    _showMapLoading();
  }

  CameraFit _fitFor(List<Place> places) {
    return CameraFit.coordinates(
      coordinates: [
        for (var i = 0; i < places.length; i++)
          PlaceMapView.pointFor(places[i], index: i),
      ],
      padding: const EdgeInsets.fromLTRB(54, 150, 78, 170),
      maxZoom: 16,
      minZoom: PlaceMapView.minZoom,
    );
  }

  void _fitAllPlaces() {
    if (widget.places.isEmpty) return;
    _showMapLoading();
    _interaction.selectPlace(null);
    if (widget.places.length == 1) {
      widget.mapController.move(PlaceMapView.pointFor(widget.places.first), 16);
    } else {
      widget.mapController.fitCamera(_fitFor(widget.places));
    }
  }

  void _selectPlace(Place place, List<Place> places) {
    final index = places.indexWhere((item) => item.id == place.id);
    _interaction.selectPlace(place.id);
    widget.mapController.move(
      PlaceMapView.pointFor(place, index: index < 0 ? 0 : index),
      widget.mapController.camera.zoom,
    );
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_placePageController.hasClients) return;
      _placePageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _scheduleCameraIdle() {
    _cameraIdleTimer?.cancel();
    _cameraIdleTimer = Timer(const Duration(milliseconds: 180), () {
      final camera = _latestCamera;
      if (!mounted || camera == null) return;
      final movedByGesture = _cameraMovedByGesture;
      _cameraMovedByGesture = false;
      _interaction.settleCamera(zoom: camera.zoom, userGesture: movedByGesture);
      if (_cameraReady) _scheduleCameraSave(camera);
    });
  }

  void _searchCurrentArea() {
    final camera = _latestCamera ?? widget.mapController.camera;
    widget.onSearchArea?.call(camera);
    _interaction.consumeAreaSearch();
  }

  String get _cameraKey => 'pinlogy_map_camera_v1_${widget.mapId}';

  Future<void> _restoreCamera() async {
    if (widget.initialCenter != null || widget.initialZoom != null) {
      _cameraReady = true;
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    final values = preferences.getStringList(_cameraKey);
    if (!mounted) return;
    if (values != null && values.length == 3) {
      final latitude = double.tryParse(values[0]);
      final longitude = double.tryParse(values[1]);
      final zoom = double.tryParse(values[2]);
      if (latitude != null &&
          longitude != null &&
          zoom != null &&
          latitude >= -90 &&
          latitude <= 90 &&
          longitude >= -180 &&
          longitude <= 180) {
        widget.mapController.move(
          LatLng(latitude, longitude),
          zoom.clamp(PlaceMapView.minZoom, PlaceMapView.maxZoom),
        );
      }
    }
    _cameraReady = true;
  }

  void _scheduleCameraSave(MapCamera camera) {
    _cameraSaveTimer?.cancel();
    _cameraSaveTimer = Timer(const Duration(milliseconds: 500), () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList(_cameraKey, [
        camera.center.latitude.toStringAsFixed(7),
        camera.center.longitude.toStringAsFixed(7),
        camera.zoom.toStringAsFixed(3),
      ]);
    });
  }
}

class _MapStatusChip extends StatelessWidget {
  const _MapStatusChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .94),
    borderRadius: BorderRadius.circular(999),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF244C39)),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _MapRetryCard extends StatelessWidget {
  const _MapRetryCard({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFF7ED),
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 19),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              '地図を読み込めませんでした',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('再試行'),
          ),
        ],
      ),
    ),
  );
}

class _PlaceCluster extends StatelessWidget {
  const _PlaceCluster({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$count件の場所を拡大して表示',
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF244C39),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3D173D30),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Center(
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedPlaceCard extends StatelessWidget {
  const _SelectedPlaceCard({
    required this.place,
    required this.positionLabel,
    required this.imagePath,
    required this.source,
    required this.onClose,
    required this.onOpen,
    required this.onDirections,
    this.onRefreshSource,
  });

  final Place place;
  final String positionLabel;
  final String? imagePath;
  final SourcePost? source;
  final VoidCallback onClose;
  final VoidCallback onOpen;
  final VoidCallback onDirections;
  final Future<String?> Function()? onRefreshSource;

  @override
  Widget build(BuildContext context) {
    final sourceLinks = SourceLinkService();
    final canOpenSource = sourceLinks.canOpen(source);
    return Material(
      color: Colors.white.withValues(alpha: .97),
      elevation: 0,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: PlacePhoto(
                    path: imagePath,
                    onRefreshSource: onRefreshSource,
                    fallback: ColoredBox(
                      color: const Color(0xFFFFEDF1),
                      child: Image(
                        image: const AssetImage(
                          'assets/images/place_fallback.webp',
                        ),
                        fit: BoxFit.cover,
                        color: Colors.white.withValues(alpha: .08),
                        colorBlendMode: BlendMode.srcOver,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      positionLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF87928C),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [place.category, place.area ?? place.address]
                          .whereType<String>()
                          .where((value) => value.trim().isNotEmpty)
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF6F7C75),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text(
                          '詳細を見る  ›',
                          style: TextStyle(
                            color: Color(0xFF205740),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (canOpenSource) ...[
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _openSource(context, sourceLinks),
                            borderRadius: BorderRadius.circular(999),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    sourceLinks.iconFor(source),
                                    size: 14,
                                    color: const Color(0xFF205740),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    sourceLinks.serviceLabel(source),
                                    style: const TextStyle(
                                      color: Color(0xFF205740),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: '経路',
                    onPressed: onDirections,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.directions_outlined, size: 20),
                  ),
                  IconButton(
                    tooltip: '閉じる',
                    onPressed: onClose,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSource(
    BuildContext context,
    SourceLinkService sourceLinks,
  ) async {
    final post = source;
    if (post == null) return;
    final opened = await sourceLinks.openPost(post);
    if (!context.mounted || opened) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('元の投稿を開けませんでした')));
  }
}

/// Apple Maps のドロップピンに近い形。
class _AppleStylePin extends StatelessWidget {
  const _AppleStylePin({
    required this.place,
    required this.imagePath,
    required this.visited,
    required this.focused,
    required this.showName,
    this.markerLabel,
    required this.onTap,
  });

  final Place place;
  final String? imagePath;
  final bool visited;
  final bool focused;
  final bool showName;
  final String? markerLabel;
  final VoidCallback onTap;
  static final Map<String, _PinStyle> _styleCache = {};

  @override
  Widget build(BuildContext context) {
    final pinStyle = _styleFor(place.category, visited: visited);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: focused ? 1.12 : 1.0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              width: imagePath == null
                  ? (focused ? 48 : 44)
                  : (focused ? 62 : 56),
              height: imagePath == null
                  ? (focused ? 48 : 44)
                  : (focused ? 62 : 56),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.rectangle,
                borderRadius: imagePath == null
                    ? BorderRadius.circular(17)
                    : BorderRadius.circular(18),
                border: Border.all(
                  color: focused ? pinStyle.color : Colors.white,
                  width: focused ? 3.5 : 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(
                      0xFF173D30,
                    ).withValues(alpha: focused ? 0.28 : 0.18),
                    blurRadius: focused ? 16 : 9,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: markerLabel != null
                  ? ColoredBox(
                      color: pinStyle.color,
                      child: Center(
                        child: Text(
                          markerLabel!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    )
                  : imagePath == null
                  ? ColoredBox(
                      color: pinStyle.color,
                      child: Center(
                        child: Icon(
                          visited ? Icons.check_rounded : pinStyle.icon,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        PlacePhoto(
                          path: imagePath,
                          fallback: ColoredBox(color: pinStyle.color),
                        ),
                        if (visited)
                          Align(
                            alignment: Alignment.topRight,
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              width: 18,
                              height: 18,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Color(0xFF57A67C),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            Transform.translate(
              offset: const Offset(0, -5),
              child: Transform.rotate(
                angle: .785,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: focused ? pinStyle.color : Colors.white,
                    border: Border(
                      right: BorderSide(
                        color: focused ? pinStyle.color : Colors.white,
                        width: 2,
                      ),
                      bottom: BorderSide(
                        color: focused ? pinStyle.color : Colors.white,
                        width: 2,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF173D30).withValues(alpha: 0.12),
                        blurRadius: 4,
                        offset: const Offset(2, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (showName)
              Container(
                constraints: const BoxConstraints(maxWidth: 126),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .92),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  place.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF244C39),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  _PinStyle _styleFor(String? category, {required bool visited}) {
    if (visited) {
      return const _PinStyle(Color(0xFF57A67C), Icons.check_rounded);
    }
    final value = (category ?? '').toLowerCase();
    return _styleCache.putIfAbsent(value, () => _uncachedStyleFor(value));
  }

  _PinStyle _uncachedStyleFor(String value) {
    if (value.contains('カフェ') || value.contains('coffee')) {
      return const _PinStyle(Color(0xFFFFA66B), Icons.local_cafe_rounded);
    }
    if (value.contains('レストラン') ||
        value.contains('飲食') ||
        value.contains('restaurant')) {
      return const _PinStyle(Color(0xFFFF6F7D), Icons.restaurant_rounded);
    }
    if (value.contains('観光') || value.contains('travel')) {
      return const _PinStyle(Color(0xFF7D8BFF), Icons.photo_camera_rounded);
    }
    if (value.contains('宿') || value.contains('hotel')) {
      return const _PinStyle(Color(0xFFB57BE8), Icons.bed_rounded);
    }
    if (value.contains('公園') || value.contains('自然')) {
      return const _PinStyle(Color(0xFF55B98A), Icons.park_rounded);
    }
    return const _PinStyle(Color(0xFFFF6F91), Icons.place_rounded);
  }
}

class _PinStyle {
  const _PinStyle(this.color, this.icon);

  final Color color;
  final IconData icon;
}

class _SoftFab extends StatelessWidget {
  const _SoftFab({
    required this.heroTag,
    required this.icon,
    this.onPressed,
    this.loading = false,
    this.tooltip,
  });

  final String heroTag;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: heroTag,
      backgroundColor: const Color(0xFFFFFBF6).withValues(alpha: 0.97),
      foregroundColor: const Color(0xFF5968DC),
      elevation: 0,
      onPressed: onPressed,
      tooltip: tooltip,
      child: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
    );
  }
}
