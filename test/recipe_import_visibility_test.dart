import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/recipe/data/recipe_sync_policy.dart';
import 'package:pinlogy/recipe/models/recipe_models.dart';

void main() {
  final start = DateTime.utc(2026, 10, 15);
  final old = start.subtract(const Duration(days: 1));
  final recent = start.add(const Duration(minutes: 1));
  bool visible(
    RecipeImportStatus status,
    DateTime time, {
    bool remote = false,
    bool terminal = false,
  }) => shouldShowImportInSession(
    status: status,
    updatedAt: time,
    sessionStartedAt: start,
    remoteActive: remote,
    localTerminal: terminal,
  );
  test('historical failures are hidden but new failures retain retry', () {
    expect(visible(RecipeImportStatus.failed, old), isFalse);
    expect(visible(RecipeImportStatus.failed, recent), isTrue);
    expect(visible(RecipeImportStatus.retryWaiting, old), isFalse);
  });
  test(
    'unconfirmed old progress is hidden; confirmed remote jobs stay visible',
    () {
      expect(visible(RecipeImportStatus.analyzing, old), isFalse);
      expect(visible(RecipeImportStatus.queued, old), isFalse);
      expect(visible(RecipeImportStatus.analyzing, old, remote: true), isTrue);
      expect(visible(RecipeImportStatus.queued, recent), isTrue);
    },
  );
  test('completed local jobs cannot leave a stale progress spinner', () {
    expect(
      visible(RecipeImportStatus.analyzing, recent, terminal: true),
      isFalse,
    );
  });
  test('selection is kept; terminal history is hidden', () {
    expect(
      visible(RecipeImportStatus.awaitingSelection, old, terminal: true),
      isTrue,
    );
    expect(visible(RecipeImportStatus.completed, old), isFalse);
    expect(visible(RecipeImportStatus.cancelled, recent), isFalse);
  });
  test('repeated result merge is stable and preserves newer user edits', () {
    final existing = Recipe(
      id: 'r',
      sourcePostId: 'p',
      title: '編集したタイトル',
      isFavorite: true,
      userEditedFields: {'title'},
      createdAt: old,
      updatedAt: recent,
    );
    final incoming = Recipe(
      id: 'r',
      sourcePostId: 'p',
      title: '解析タイトル',
      createdAt: old,
      updatedAt: start,
    );
    final once = mergeAnalyzedRecipe(
      existing: existing,
      incoming: incoming,
      saveAutomatically: true,
    );
    final twice = mergeAnalyzedRecipe(
      existing: once,
      incoming: incoming,
      saveAutomatically: true,
    );
    expect(once.title, existing.title);
    expect(once.isFavorite, isTrue);
    expect(once.updatedAt, recent);
    expect(twice.toJson(), once.toJson());
    final newer = incoming.copyWith(
      title: '新解析',
      updatedAt: recent.add(const Duration(minutes: 1)),
    );
    final result = mergeAnalyzedRecipe(
      existing: once,
      incoming: newer,
      saveAutomatically: true,
    );
    expect(result.updatedAt, newer.updatedAt);
    expect(result.title, existing.title);
  });
}
