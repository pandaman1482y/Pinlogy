import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pinlogy/controllers/pinlogy_map_interaction_controller.dart';
import 'package:pinlogy/models/models.dart';
import 'package:pinlogy/services/map_cluster_service.dart';

void main() {
  test('地図移動中ではなく停止時にズームと検索表示を更新する', () {
    final state = PinlogyMapInteractionController(initialZoom: 12);
    addTearDown(state.dispose);

    state.settleCamera(zoom: 13, userGesture: true);
    expect(state.settledZoom.value, 13);
    expect(state.areaSearchAvailable.value, isTrue);

    state.consumeAreaSearch();
    expect(state.areaSearchAvailable.value, isFalse);

    state.selectPlace('place-1');
    expect(state.selectedPlaceId.value, 'place-1');
    expect(state.settledZoom.value, 13);
  });

  test('近い100地点を低ズームではクラスタ化し、高ズームでは個別表示する', () {
    final places = List.generate(
      100,
      (index) => Place(
        name: '場所$index',
        latitude: 34.70 + (index % 10) * .0001,
        longitude: 135.49 + (index ~/ 10) * .0001,
      ),
    );
    LatLng pointFor(Place place, int _) =>
        LatLng(place.latitude!, place.longitude!);

    final clustered = clusterMapPlaces(places, 11, pointFor: pointFor);
    final expanded = clusterMapPlaces(places, 16, pointFor: pointFor);

    expect(clustered.length, lessThan(places.length));
    expect(clustered.expand((group) => group.places).length, places.length);
    expect(expanded.length, places.length);
  });
}
