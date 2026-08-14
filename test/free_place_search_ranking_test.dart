import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/services/free_place_search_service.dart';
import 'package:pinlogy/services/location_services.dart';

void main() {
  test('店名検索では住所文字列より店舗名を優先する', () {
    final addressOnly = PlaceSearchHit(
      name: '大阪府大阪市北区芝田1丁目',
      address: '大阪府大阪市北区芝田1丁目 吉野家付近',
    );
    final shop = PlaceSearchHit(name: '吉野家 芝田店', address: '大阪府大阪市北区芝田1丁目');

    final ranked = FreePlaceSearchService.rankAndMerge('吉野家', [
      addressOnly,
      shop,
    ], const []);

    expect(ranked.first.name, '吉野家 芝田店');
  });
}
