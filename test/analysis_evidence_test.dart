import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/models/models.dart';

void main() {
  test('解析候補の根拠画像番号をJSONで保持する', () {
    final candidate = ExtractionCandidate(
      name: '吉野家 芝田店',
      evidenceSummary: '画像3枚目の店名表記',
      evidenceImageIndex: 2,
      confidencePercent: 91,
    );

    final restored = ExtractionCandidate.fromJson(candidate.toJson());

    expect(restored.evidenceImageIndex, 2);
    expect(restored.confidencePercent, 91);
  });

  test('TikTok写真投稿の最大5枚の保存先を応答で受け取れる', () {
    final response = PostAnalysisResponse.fromJson({
      'source_post_id': 'post-1',
      'candidates': const [],
      'preview_image_path': '/tmp/photo_0.jpg',
      'preview_image_paths': const [
        '/tmp/photo_0.jpg',
        '/tmp/photo_1.jpg',
        '/tmp/photo_2.jpg',
      ],
    });

    expect(response.previewImagePath, '/tmp/photo_0.jpg');
    expect(response.previewImagePaths, hasLength(3));
  });
}
