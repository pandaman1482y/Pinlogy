import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/place.dart';

/// 外部地図アプリで経路案内を開く。
class DirectionsService {
  static const maxExternalStops = 10;

  Future<bool> openDirections(Place place, {DirectionsApp? preferred}) async {
    final lat = place.latitude;
    final lng = place.longitude;
    if (lat == null || lng == null) {
      if (place.address == null || place.address!.isEmpty) {
        return false;
      }
      final query = Uri.encodeComponent(place.address!);
      final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$query',
      );
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    final app = preferred ?? _defaultApp();
    final uri = switch (app) {
      DirectionsApp.googleMaps => Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
      ),
      DirectionsApp.appleMaps => Uri.parse(
        'https://maps.apple.com/?daddr=$lat,$lng',
      ),
    };
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// 並び順を維持したまま、複数スポットをGoogle Mapsへ経由地として渡す。
  /// 出発地点はGoogle Maps側の現在地、最後を目的地、それ以外を経由地にする。
  Future<bool> openMultiStopDirections(
    List<Place> places, {
    String travelMode = 'driving',
  }) async {
    final located = places.where(_hasLocation).take(maxExternalStops).toList();
    if (located.isEmpty) return false;
    if (located.length == 1) {
      return openDirections(located.first, preferred: DirectionsApp.googleMaps);
    }

    final parameters = <String, String>{
      'api': '1',
      'destination': _locationValue(located.last),
      'travelmode': travelMode,
      'dir_action': 'navigate',
    };
    final waypoints = located
        .take(located.length - 1)
        .map(_locationValue)
        .join('|');
    if (waypoints.isNotEmpty) parameters['waypoints'] = waypoints;

    final uri = Uri.https('www.google.com', '/maps/dir/', parameters);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  bool _hasLocation(Place place) =>
      (place.latitude != null && place.longitude != null) ||
      place.address?.trim().isNotEmpty == true;

  String _locationValue(Place place) {
    if (place.latitude != null && place.longitude != null) {
      return '${place.latitude},${place.longitude}';
    }
    return place.address!.trim();
  }

  DirectionsApp _defaultApp() {
    if (!kIsWeb && Platform.isIOS) {
      return DirectionsApp.appleMaps;
    }
    return DirectionsApp.googleMaps;
  }
}

enum DirectionsApp { googleMaps, appleMaps }
