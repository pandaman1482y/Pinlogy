import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/models/models.dart';
import 'package:pinlogy/services/local_post_analysis_service.dart';

void main() {
  test('投稿文から住所を優先して複数店舗を抽出する', () async {
    final result = await LocalPostAnalysisService().analyze(
      const PostAnalysisRequest(
        sourcePostId: 'post-1',
        text: '''
喫茶ソワレ
京都府京都市下京区西木屋町通四条上る真町95
営業時間 10:00〜19:30
定休日：火曜日

イノダコーヒ 本店
京都府京都市中京区道祐町140
''',
      ),
    );

    expect(result.candidates, hasLength(2));
    expect(result.candidates.first.name, '喫茶ソワレ');
    expect(result.candidates.first.address, contains('京都府京都市'));
    expect(result.candidates.first.latitude, isNull);
    expect(result.candidates.first.match, PlaceMatchConfidence.needsReview);
    expect(result.candidates.first.openingTimeMinutes, 600);
    expect(result.candidates.first.closingTimeMinutes, 1170);
    expect(result.candidates.first.closedWeekdays, [2]);
  });

  test('住所がない投稿文も確認用候補として残す', () async {
    final result = await LocalPostAnalysisService().analyze(
      const PostAnalysisRequest(sourcePostId: 'post-2', text: '週末に行きたいカフェ'),
    );

    expect(result.candidates, hasLength(1));
    expect(result.candidates.single.name, '週末に行きたいカフェ');
    expect(result.candidates.single.confidencePercent, 40);
  });
}
