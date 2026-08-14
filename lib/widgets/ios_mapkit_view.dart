import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';

/// 本番地図を置き換えず、iPhone実機でMapKitをA/B比較するための隔離ビュー。
class IosMapKitView extends StatefulWidget {
  const IosMapKitView({
    super.key,
    required this.places,
    this.onPlaceSelected,
    this.onCameraIdle,
  });

  final List<Place> places;
  final ValueChanged<String>? onPlaceSelected;
  final ValueChanged<Map<String, double>>? onCameraIdle;

  static Map<String, Object?> creationParams(List<Place> places) => {
    'places': [for (final place in places) _placeJson(place)],
  };

  static Map<String, Object?> _placeJson(Place place) => {
    'id': place.id,
    'name': place.name,
    'category': place.category,
    'latitude': place.latitude,
    'longitude': place.longitude,
  };

  @override
  State<IosMapKitView> createState() => _IosMapKitViewState();
}

class _IosMapKitViewState extends State<IosMapKitView> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(covariant IosMapKitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.places, widget.places)) _updatePlaces();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return const ColoredBox(
        color: Color(0xFFF1F3F2),
        child: Center(child: Text('MapKit比較はiPhone実機で利用できます')),
      );
    }
    return UiKitView(
      viewType: 'com.pinlogy/mapkit',
      layoutDirection: TextDirection.ltr,
      creationParams: IosMapKitView.creationParams(widget.places),
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (viewId) {
        final channel = MethodChannel('com.pinlogy/mapkit_$viewId');
        _channel = channel;
        channel.setMethodCallHandler(_handleNativeCall);
      },
    );
  }

  Future<void> _updatePlaces() async {
    await _channel?.invokeMethod<void>(
      'updatePlaces',
      IosMapKitView.creationParams(widget.places),
    );
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'placeSelected') {
      final id = (call.arguments as Map?)?['id']?.toString();
      if (id != null) widget.onPlaceSelected?.call(id);
      return;
    }
    if (call.method == 'cameraIdle') {
      final raw = call.arguments;
      if (raw is! Map) return;
      final values = <String, double>{};
      for (final entry in raw.entries) {
        if (entry.key is String && entry.value is num) {
          values[entry.key as String] = (entry.value as num).toDouble();
        }
      }
      widget.onCameraIdle?.call(values);
    }
  }
}

class MapKitComparisonPage extends StatefulWidget {
  const MapKitComparisonPage({super.key, required this.places});

  final List<Place> places;

  @override
  State<MapKitComparisonPage> createState() => _MapKitComparisonPageState();
}

class _MapKitComparisonPageState extends State<MapKitComparisonPage> {
  String? _selectedPlaceId;

  @override
  Widget build(BuildContext context) {
    final selected = widget.places
        .where((place) => place.id == _selectedPlaceId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MapKit実機比較'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(30),
          child: Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('滑らかさ・ズーム・100件ピン・クラスタを確認'),
          ),
        ),
      ),
      body: Stack(
        children: [
          IosMapKitView(
            places: widget.places,
            onPlaceSelected: (id) => setState(() => _selectedPlaceId = id),
          ),
          if (selected != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.place_rounded),
                  title: Text(selected.name),
                  subtitle: Text(
                    selected.address ?? selected.category ?? '詳細未設定',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
