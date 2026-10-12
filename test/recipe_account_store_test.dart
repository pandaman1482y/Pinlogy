import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/recipe/data/recipe_store.dart';
import 'package:pinlogy/recipe/models/recipe_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('アカウントごとにレシピスナップショットを分離する', () async {
    final store = SharedPreferencesRecipeStore();
    final accountA = RecipeSnapshot(
      recipes: [_recipe('recipe-a', 'アカウントAのレシピ')],
    );
    final accountB = RecipeSnapshot(
      recipes: [_recipe('recipe-b', 'アカウントBのレシピ')],
    );

    await store.save(accountA, ownerId: 'user-a');
    await store.save(accountB, ownerId: 'user-b');

    expect(
      (await store.load(ownerId: 'user-a')).recipes.single.title,
      'アカウントAのレシピ',
    );
    expect(
      (await store.load(ownerId: 'user-b')).recipes.single.title,
      'アカウントBのレシピ',
    );
    expect((await store.load()).recipes, isEmpty);
  });

  test('旧端末データは最初にログインしたアカウントだけへ移行する', () async {
    final legacy = RecipeSnapshot(recipes: [_recipe('legacy', '以前の端末レシピ')]);
    SharedPreferences.setMockInitialValues({
      'pinlogy_recipe_snapshot_v1': _encode(legacy),
    });
    final store = SharedPreferencesRecipeStore();

    final migrated = await store.load(
      ownerId: 'first-user',
      migrateLegacy: true,
    );
    final second = await store.load(
      ownerId: 'second-user',
      migrateLegacy: true,
    );

    expect(migrated.recipes.single.title, '以前の端末レシピ');
    expect(second.recipes, isEmpty);
  });

  test('500件のレシピと端末画像パスをアカウント別に復元する', () async {
    final store = SharedPreferencesRecipeStore();
    final snapshot = RecipeSnapshot(
      recipes: List.generate(
        500,
        (index) => Recipe(
          id: 'recipe-$index',
          sourcePostId: 'source-$index',
          title: 'レシピ$index',
          coverImagePath: '/cached/account-a/recipe-$index.jpg',
        ),
      ),
    );

    await store.save(snapshot, ownerId: 'account-a');
    final restored = await store.load(ownerId: 'account-a');

    expect(restored.recipes, hasLength(500));
    expect(
      restored.recipes[321].coverImagePath,
      '/cached/account-a/recipe-321.jpg',
    );
    expect((await store.load(ownerId: 'account-b')).recipes, isEmpty);
  });

  test('破損した主スナップショットはバックアップから復元する', () async {
    final directory = await Directory.systemTemp.createTemp('recipe-store-');
    addTearDown(() => directory.delete(recursive: true));
    final store = SharedPreferencesRecipeStore(
      directoryProvider: () async => directory,
    );
    await store.save(
      RecipeSnapshot(recipes: [_recipe('first', 'バックアップ対象')]),
      ownerId: 'user-a',
    );
    await store.save(
      RecipeSnapshot(recipes: [_recipe('second', '現在値')]),
      ownerId: 'user-a',
    );
    final primary = File('${directory.path}/recipe_snapshots/user-a.json');
    await primary.writeAsString('{broken', flush: true);

    final restored = await store.load(ownerId: 'user-a');
    expect(restored.recipes.single.title, 'バックアップ対象');
  });

  test('旧SharedPreferencesデータをアカウント別ファイルへ自動移行する', () async {
    final directory = await Directory.systemTemp.createTemp('recipe-store-');
    addTearDown(() => directory.delete(recursive: true));
    final legacy = RecipeSnapshot(recipes: [_recipe('legacy-file', '移行対象')]);
    SharedPreferences.setMockInitialValues({
      'pinlogy_recipe_snapshot_v1': _encode(legacy),
    });
    final store = SharedPreferencesRecipeStore(
      directoryProvider: () async => directory,
    );

    final restored = await store.load(
      ownerId: 'file-user',
      migrateLegacy: true,
    );
    final file = File('${directory.path}/recipe_snapshots/file-user.json');

    expect(restored.recipes.single.title, '移行対象');
    expect(await file.exists(), isTrue);
    expect((await file.readAsString()), contains('移行対象'));
  });
}

Recipe _recipe(String id, String title) =>
    Recipe(id: id, sourcePostId: 'source-$id', title: title);

String _encode(RecipeSnapshot snapshot) {
  return jsonEncode(snapshot.toJson());
}
