import 'dart:convert';

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
}

Recipe _recipe(String id, String title) =>
    Recipe(id: id, sourcePostId: 'source-$id', title: title);

String _encode(RecipeSnapshot snapshot) {
  return jsonEncode(snapshot.toJson());
}
