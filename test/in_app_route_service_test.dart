import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/services/in_app_route_service.dart';

void main() {
  test('OSRM GeoJSON responseを経路へ変換する', () {
    const body = '''{
      "code":"Ok",
      "routes":[{
        "distance":1250.5,
        "duration":420.0,
        "geometry":{"type":"LineString","coordinates":[[139.70,35.68],[139.71,35.69]]},
        "legs":[{"steps":[
          {"distance":100,"duration":30,"name":"中央通り","maneuver":{"type":"depart","modifier":"straight"}},
          {"distance":50,"duration":10,"name":"","maneuver":{"type":"arrive"}}
        ]}]
      }]
    }''';

    final route = InAppRouteService.parseRouteResponse(body);
    expect(route.points, hasLength(2));
    expect(route.points.first.latitude, 35.68);
    expect(route.points.first.longitude, 139.70);
    expect(route.distanceMeters, 1250.5);
    expect(route.durationSeconds, 420);
    expect(route.steps.first.instruction, '中央通りを進む');
    expect(route.steps.last.instruction, '目的地に到着');
  });

  test('経路なしレスポンスはエラーにする', () {
    expect(
      () => InAppRouteService.parseRouteResponse(
        '{"code":"NoRoute","routes":[]}',
      ),
      throwsStateError,
    );
  });

  test('HTTPS以外のAPIは設定済みとして扱わない', () {
    expect(InAppRouteService(baseUrl: '').isConfigured, isFalse);
    expect(
      InAppRouteService(baseUrl: 'http://example.com').isConfigured,
      isFalse,
    );
    expect(
      InAppRouteService(baseUrl: 'https://example.com').isConfigured,
      isTrue,
    );
  });

  test('車・徒歩・自転車の経路プロファイルを使い分ける', () {
    expect(RouteTravelMode.driving.profile, 'driving');
    expect(RouteTravelMode.walking.profile, 'walking');
    expect(RouteTravelMode.cycling.profile, 'cycling');
  });
}
