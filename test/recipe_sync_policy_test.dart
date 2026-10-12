import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/recipe/data/recipe_sync_policy.dart';
import 'package:pinlogy/recipe/models/recipe_models.dart';

void main() {
  final old = DateTime.utc(2026, 10, 10, 10);
  final current = DateTime.utc(2026, 10, 10, 11);

  test('初回同期はクラウドスナップショットを取得する', () {
    expect(
      shouldDownloadRecipeSnapshot(
        remoteUpdatedAt: current,
        knownUpdatedAt: null,
      ),
      isTrue,
    );
  });

  test('更新日時が同じなら重いpayloadと画像を再取得しない', () {
    expect(
      shouldDownloadRecipeSnapshot(
        remoteUpdatedAt: current,
        knownUpdatedAt: current,
      ),
      isFalse,
    );
  });

  test('クラウドが新しい場合だけ差分を取得する', () {
    expect(
      shouldDownloadRecipeSnapshot(
        remoteUpdatedAt: current,
        knownUpdatedAt: old,
      ),
      isTrue,
    );
    expect(
      shouldDownloadRecipeSnapshot(
        remoteUpdatedAt: old,
        knownUpdatedAt: current,
      ),
      isFalse,
    );
  });

  test('クラウドデータがなければダウンロードしない', () {
    expect(
      shouldDownloadRecipeSnapshot(
        remoteUpdatedAt: null,
        knownUpdatedAt: current,
      ),
      isFalse,
    );
  });

  Recipe recipe({
    required String title,
    required List<RecipeStep> steps,
    Set<String>? edited,
  }) => Recipe(
    id: 'recipe-1',
    sourcePostId: 'post-1',
    title: title,
    parts: [RecipePart(id: 'part-1', name: '本体', steps: steps)],
    userEditedFields: edited,
  );

  test('旧データが工程0件なら編集フラグがあっても最新工程で修復する', () {
    final existing = recipe(
      title: 'ユーザー編集タイトル',
      steps: const [],
      edited: {'title', 'parts'},
    );
    final incoming = recipe(
      title: 'AIタイトル',
      steps: [RecipeStep(order: 1, instruction: '卵を溶く')],
    );

    final merged = mergeAnalyzedRecipe(
      existing: existing,
      incoming: incoming,
      saveAutomatically: true,
    );

    expect(merged.title, 'ユーザー編集タイトル');
    expect(merged.allSteps.single.instruction, '卵を溶く');
    expect(merged.isSaved, isTrue);
  });

  test('ユーザーが編集した工程は再同期でも保持する', () {
    final existing = recipe(
      title: 'レシピ',
      steps: [RecipeStep(order: 1, instruction: '弱火で焼く')],
      edited: {'parts'},
    );
    final incoming = recipe(
      title: 'レシピ',
      steps: [RecipeStep(order: 1, instruction: '強火で焼く')],
    );

    final merged = mergeAnalyzedRecipe(
      existing: existing,
      incoming: incoming,
      saveAutomatically: true,
    );

    expect(merged.allSteps.single.instruction, '弱火で焼く');
  });
}
