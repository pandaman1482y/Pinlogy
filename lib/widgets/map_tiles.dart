import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Pinlogyで選べる地図の見た目。
enum MapTileStyle { clear, stores }

extension MapTileStyleLabel on MapTileStyle {
  String get label => switch (this) {
    MapTileStyle.clear => '日本語・標準地図',
    MapTileStyle.stores => 'やさしい地図',
  };

  String get description => switch (this) {
    MapTileStyle.clear => '道路や施設名を詳しく表示',
    MapTileStyle.stores => '保存したピンが見やすい淡色表示',
  };
}

abstract final class PinlogyMapTiles {
  /// 明るく色のある、標準のポップ地図。
  static const clearUrlTemplate = String.fromEnvironment(
    'MAP_TILE_URL_TEMPLATE',
    defaultValue:
        'https://tile.openstreetmap.jp/styles/osm-bright-ja/{z}/{x}/{y}.png',
  );

  /// ピンを主役にする淡色地図。
  static const storesUrlTemplate =
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

  static const clearAttribution = String.fromEnvironment(
    'MAP_TILE_ATTRIBUTION',
    defaultValue: '© OpenStreetMap Japan',
  );
  static const storesAttribution = '© OpenStreetMap © CARTO';
  static const japaneseAttributionUrl =
      'https://www.openstreetmap.org/copyright';

  // 既存コードとの互換用エイリアス。
  static const detailedUrlTemplate = clearUrlTemplate;
  static const simpleUrlTemplate = storesUrlTemplate;
  static const softUrlTemplate = clearUrlTemplate;
  static const japaneseUrlTemplate = clearUrlTemplate;
  static const paleUrlTemplate = storesUrlTemplate;
  static const standardUrlTemplate = clearUrlTemplate;

  static final NetworkTileProvider _tileProvider = NetworkTileProvider(
    silenceExceptions: true,
    abortObsoleteRequests: true,
    // 表示済みタイルをOS管理のキャッシュ領域へ保存し、再表示時に再利用する。
    cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
      maxCacheSize: 256 * 1024 * 1024,
    ),
  );

  static String attributionFor(MapTileStyle style) => switch (style) {
    MapTileStyle.clear => clearAttribution,
    MapTileStyle.stores => storesAttribution,
  };

  static TileLayer buildLayer({
    MapTileStyle style = MapTileStyle.clear,
    Stream<void>? reset,
    ErrorTileCallBack? onError,
  }) {
    final colorful = style == MapTileStyle.clear;
    return TileLayer(
      key: ValueKey(
        colorful ? 'tiles-osm-japan-bright' : 'tiles-carto-voyager',
      ),
      urlTemplate: colorful ? clearUrlTemplate : storesUrlTemplate,
      subdomains: colorful ? const [] : const ['a', 'b', 'c', 'd'],
      userAgentPackageName: 'com.pinlogy.pinlogy',
      // OSM Japanは高ズームの実タイルがないため、18以降は安全に拡大表示する。
      maxNativeZoom: colorful ? 18 : 20,
      maxZoom: 20,
      minZoom: 3,
      // Keep the previous zoom level visible until the next set is complete.
      // This avoids a blank background during quick pinch gestures.
      keepBuffer: 4,
      panBuffer: 2,
      tileDisplay: const TileDisplay.instantaneous(),
      tileUpdateTransformer: TileUpdateTransformers.debounce(
        const Duration(milliseconds: 70),
      ),
      tileProvider: _tileProvider,
      reset: reset,
      errorTileCallback: onError,
      evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
    );
  }

  static const mapBackground = Color(0xFFF1F6F4);

  /// 初回表示前に、指定地点周辺の3×3タイルをFlutterの画像キャッシュへ入れる。
  /// 失敗しても通常の地図読み込みへフォールバックする。
  static Future<void> preloadAround(
    BuildContext context, {
    required double latitude,
    required double longitude,
    double zoom = 15,
    MapTileStyle style = MapTileStyle.stores,
  }) async {
    final futures = <Future<void>>[];
    final centerZoom = zoom.round().clamp(3, 18);
    final urlTemplate = style == MapTileStyle.stores
        ? storesUrlTemplate
        : clearUrlTemplate;
    for (final z in {centerZoom - 1, centerZoom, centerZoom + 1}) {
      if (z < 3 || z > 20) continue;
      final count = 1 << z;
      final x = ((longitude + 180) / 360 * count).floor();
      final latRad = latitude * math.pi / 180;
      final y =
          ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
                  2 *
                  count)
              .floor();
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          final tileX = (x + dx).clamp(0, count - 1);
          final tileY = (y + dy).clamp(0, count - 1);
          final url = urlTemplate
              .replaceAll('{s}', 'a')
              .replaceAll('{z}', '$z')
              .replaceAll('{x}', '$tileX')
              .replaceAll('{y}', '$tileY');
          futures.add(
            precacheImage(
              NetworkImage(url),
              context,
              onError: (error, stackTrace) {},
            ),
          );
        }
      }
    }
    await Future.wait(futures);
  }

  static Widget attributionBadge(MapTileStyle style) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 12)],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          attributionFor(style),
          style: const TextStyle(fontSize: 9, color: Color(0xFF69756F)),
        ),
      ),
    );
  }
}
