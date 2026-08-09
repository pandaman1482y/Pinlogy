import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/services/free_place_search_service.dart';

void main() {
  test('GSI住所検索JSONをPlaceSearchHitに変換できる', () {
    const body = '''
[
  {
    "geometry": { "coordinates": [139.7671, 35.6812], "type": "Point" },
    "type": "Feature",
    "properties": { "addressCode": "13101", "title": "東京駅" }
  }
]
''';
    final hits = FreePlaceSearchService.parseGsiResponse(body);
    expect(hits, hasLength(1));
    expect(hits.first.name, '東京駅');
    expect(hits.first.latitude, closeTo(35.6812, 0.0001));
    expect(hits.first.longitude, closeTo(139.7671, 0.0001));
  });

  test('Nominatim JSONをPlaceSearchHitに変換できる', () {
    const body = '''
[
  {
    "lat": "34.9995",
    "lon": "135.7681",
    "name": "喫茶ソワレ",
    "display_name": "喫茶ソワレ, 京都市, 京都府, 日本",
    "osm_type": "node",
    "osm_id": 123
  }
]
''';
    final hits = FreePlaceSearchService.parseNominatimResponse(body);
    expect(hits, hasLength(1));
    expect(hits.first.name, '喫茶ソワレ');
    expect(hits.first.address, contains('京都市'));
  });
}
