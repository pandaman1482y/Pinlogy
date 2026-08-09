import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class InAppRoute {
  const InAppRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final List<InAppRouteStep> steps;
}

class InAppRouteStep {
  const InAppRouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final String instruction;
  final double distanceMeters;
  final double durationSeconds;
}

enum RouteTravelMode {
  driving('driving', '車'),
  walking('walking', '徒歩'),
  cycling('cycling', '自転車');

  const RouteTravelMode(this.profile, this.label);
  final String profile;
  final String label;
}

/// OSRM互換APIを利用する経路サービス。
/// 公開版では --dart-define=ROUTING_API_BASE_URL=https://... を必ず指定する。
class InAppRouteService {
  InAppRouteService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl =
          (baseUrl ?? const String.fromEnvironment('ROUTING_API_BASE_URL'))
              .replaceAll(RegExp(r'/$'), '');

  final http.Client _client;
  final String baseUrl;

  bool get isConfigured => baseUrl.startsWith('https://');

  Future<InAppRoute> drivingRoute({
    required LatLng origin,
    required LatLng destination,
  }) => route(origin: origin, destination: destination);

  Future<InAppRoute> route({
    required LatLng origin,
    required LatLng destination,
    RouteTravelMode mode = RouteTravelMode.driving,
  }) async {
    if (!isConfigured) {
      throw StateError('アプリ内経路APIが設定されていません');
    }
    final uri =
        Uri.parse(
          '$baseUrl/route/v1/${mode.profile}/'
          '${origin.longitude},${origin.latitude};'
          '${destination.longitude},${destination.latitude}',
        ).replace(
          queryParameters: const {
            'overview': 'full',
            'geometries': 'geojson',
            'steps': 'true',
          },
        );
    final response = await _client
        .get(uri, headers: const {'User-Agent': 'Pinlogy/1.0'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('経路を取得できませんでした (${response.statusCode})');
    }
    return parseRouteResponse(response.body);
  }

  static InAppRoute parseRouteResponse(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['code'] != 'Ok') throw StateError('経路が見つかりませんでした');
    final routes = json['routes'] as List? ?? const [];
    if (routes.isEmpty) throw StateError('経路が見つかりませんでした');
    final route = routes.first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>?;
    final coordinates = geometry?['coordinates'] as List? ?? const [];
    final points = coordinates
        .map((item) {
          final pair = item as List;
          return LatLng(
            (pair[1] as num).toDouble(),
            (pair[0] as num).toDouble(),
          );
        })
        .toList(growable: false);
    if (points.length < 2) throw StateError('経路の形状を取得できませんでした');

    final legs = route['legs'] as List? ?? const [];
    final steps = <InAppRouteStep>[];
    for (final legValue in legs) {
      final leg = legValue as Map<String, dynamic>;
      for (final stepValue in (leg['steps'] as List? ?? const [])) {
        final step = stepValue as Map<String, dynamic>;
        final maneuver = step['maneuver'] as Map<String, dynamic>? ?? const {};
        steps.add(
          InAppRouteStep(
            instruction: _instruction(maneuver, step['name'] as String? ?? ''),
            distanceMeters: (step['distance'] as num? ?? 0).toDouble(),
            durationSeconds: (step['duration'] as num? ?? 0).toDouble(),
          ),
        );
      }
    }
    return InAppRoute(
      points: points,
      distanceMeters: (route['distance'] as num? ?? 0).toDouble(),
      durationSeconds: (route['duration'] as num? ?? 0).toDouble(),
      steps: steps,
    );
  }

  static String _instruction(Map<String, dynamic> maneuver, String road) {
    final type = maneuver['type'] as String? ?? '';
    final modifier = maneuver['modifier'] as String? ?? '';
    if (type == 'depart') return road.isEmpty ? '出発' : '$roadを進む';
    if (type == 'arrive') return '目的地に到着';
    final action = switch (modifier) {
      'left' || 'sharp left' || 'slight left' => '左方向へ',
      'right' || 'sharp right' || 'slight right' => '右方向へ',
      'uturn' => '折り返す',
      _ => '直進',
    };
    return road.isEmpty ? action : '$roadへ$action';
  }
}
