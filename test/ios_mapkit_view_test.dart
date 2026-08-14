import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/models/models.dart';
import 'package:pinlogy/widgets/ios_mapkit_view.dart';

void main() {
  test('MapKit比較ビューへ共通Placeデータを渡す', () {
    final place = Place(
      id: 'place-1',
      name: '喫茶ソワレ',
      category: '飲食店',
      latitude: 34.9995,
      longitude: 135.7681,
    );

    final params = IosMapKitView.creationParams([place]);
    final places = params['places']! as List<Object?>;
    final encoded = places.single! as Map<String, Object?>;

    expect(encoded['id'], 'place-1');
    expect(encoded['latitude'], 34.9995);
    expect(encoded['category'], '飲食店');
  });
}
