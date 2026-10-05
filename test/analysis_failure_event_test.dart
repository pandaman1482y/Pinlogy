import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/services/share_receiver_service.dart';

void main() {
  AnalysisFailureEvent event(String message) => AnalysisFailureEvent(
    jobId: 'job-1',
    sourcePostId: 'post-1',
    message: message,
  );

  test('回数不足を判定する', () {
    expect(event('解析回数が不足しています。').creditsExhausted, isTrue);
  });

  test('使用禁止投稿・投稿者を判定する', () {
    expect(event('この投稿者の投稿は権利者からの申し出により登録できません。').blocked, isTrue);
  });

  test('レシピ未検出を判定する', () {
    expect(event('レシピを検出できませんでした。').recipeNotFound, isTrue);
  });
}
