import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/services/ai_post_analysis_service.dart';
import 'package:pinlogy/widgets/map_tiles.dart';

void main() {
  test('InstagramとTikTokの公開投稿URLを画像再取得対象にする', () {
    expect(
      AiPostAnalysisService.supportsRemotePreviewUrl(
        'https://www.instagram.com/p/example/',
      ),
      isTrue,
    );
    expect(
      AiPostAnalysisService.supportsRemotePreviewUrl(
        'https://www.tiktok.com/@example/photo/123',
      ),
      isTrue,
    );
  });

  test('偽装ドメインやHTTPは画像再取得対象にしない', () {
    expect(
      AiPostAnalysisService.supportsRemotePreviewUrl(
        'https://instagram.com.example.com/p/fake',
      ),
      isFalse,
    );
    expect(
      AiPostAnalysisService.supportsRemotePreviewUrl(
        'http://www.instagram.com/p/example/',
      ),
      isFalse,
    );
  });

  test('地図の種類に用途の違いが分かる表示名がある', () {
    expect(MapTileStyle.clear.label, contains('日本語'));
    expect(MapTileStyle.stores.label, contains('やさしい'));
    expect(
      MapTileStyle.values.every((style) => style.description.isNotEmpty),
      isTrue,
    );
  });
}
