import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/core/errors.dart';
import 'package:pinlogy/models/models.dart';
import 'package:pinlogy/widgets/map_tiles.dart';
import 'package:pinlogy/widgets/place_map_view.dart';

void main() {
  test('toUserMessage は StateError 内のネットワーク文言も翻訳する', () {
    expect(
      toUserMessage(StateError('SocketException: Failed host lookup')),
      contains('ネットワーク'),
    );
  });

  test('toUserMessage は StateError の日本語をそのまま返す', () {
    expect(toUserMessage(StateError('マップが見つかりません')), 'マップが見つかりません');
  });

  test('toUserMessage はネットワークエラーを翻訳する', () {
    expect(
      toUserMessage(Exception('SocketException: Failed host lookup')),
      contains('ネットワーク'),
    );
  });

  test('匿名ログイン無効時はアカウント設定を案内する', () {
    expect(
      toUserMessage(Exception('anonymous_provider_disabled')),
      contains('アカウントを設定'),
    );
  });

  test('PlaceMapView.pointFor は緯度経度を優先する', () {
    final place = Place(
      name: 'テスト',
      latitude: 35.0,
      longitude: 135.0,
      mapPinX: 0.9,
      mapPinY: 0.9,
    );
    final point = PlaceMapView.pointFor(place);
    expect(point.latitude, 35.0);
    expect(point.longitude, 135.0);
  });

  test('デフォルトは目印を表示する日本語Bright地図', () {
    expect(PinlogyMapTiles.clearUrlTemplate, contains('openstreetmap.jp'));
    expect(PinlogyMapTiles.clearUrlTemplate, contains('osm-bright-ja'));
    expect(PinlogyMapTiles.storesUrlTemplate, contains('cartocdn.com'));
    expect(PinlogyMapTiles.storesUrlTemplate, contains('voyager'));
  });
}
