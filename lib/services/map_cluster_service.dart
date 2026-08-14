import 'package:latlong2/latlong.dart';

import '../models/models.dart';

class MapMarkerGroup {
  MapMarkerGroup({required this.places, required this.center});

  final List<Place> places;
  LatLng center;

  void add(Place place, LatLng point) {
    final count = places.length;
    center = LatLng(
      (center.latitude * count + point.latitude) / (count + 1),
      (center.longitude * count + point.longitude) / (count + 1),
    );
    places.add(place);
  }
}

/// カメラ停止後にだけ呼び出す、保存済み地点用の軽量クラスタ計算。
List<MapMarkerGroup> clusterMapPlaces(
  List<Place> places,
  double zoom, {
  required LatLng Function(Place place, int index) pointFor,
}) {
  if (zoom >= 15 || places.length < 2) {
    return [
      for (var i = 0; i < places.length; i++)
        MapMarkerGroup(places: [places[i]], center: pointFor(places[i], i)),
    ];
  }

  final threshold = 360 / (1 << zoom.floor()) * .34;
  final groups = <MapMarkerGroup>[];
  final cells = <(int, int), List<MapMarkerGroup>>{};

  for (var i = 0; i < places.length; i++) {
    final place = places[i];
    final point = pointFor(place, i);
    final cell = (
      (point.latitude / threshold).floor(),
      (point.longitude / threshold).floor(),
    );
    MapMarkerGroup? match;
    for (var latOffset = -1; latOffset <= 1 && match == null; latOffset++) {
      for (var lngOffset = -1; lngOffset <= 1 && match == null; lngOffset++) {
        for (final candidate
            in cells[(cell.$1 + latOffset, cell.$2 + lngOffset)] ??
                const <MapMarkerGroup>[]) {
          if ((candidate.center.latitude - point.latitude).abs() <= threshold &&
              (candidate.center.longitude - point.longitude).abs() <=
                  threshold) {
            match = candidate;
            break;
          }
        }
      }
    }
    if (match != null) {
      match.add(place, point);
      continue;
    }
    final group = MapMarkerGroup(places: [place], center: point);
    groups.add(group);
    cells.putIfAbsent(cell, () => []).add(group);
  }
  return groups;
}
