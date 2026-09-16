import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/app/app.dart';
import 'package:pinlogy/app/app_scope.dart';
import 'package:pinlogy/app/pinlogy_controller.dart';
import 'package:pinlogy/recipe/data/recipe_store.dart';
import 'package:pinlogy/recipe/models/recipe_models.dart';
import 'package:pinlogy/recipe/recipe_controller.dart';
import 'package:pinlogy/recipe/recipe_scope.dart';
import 'package:pinlogy/repositories/local_data_store.dart';
import 'package:pinlogy/services/device_location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<({PinlogyController legacy, RecipeController recipes})> pumpRecipeApp(
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues({
    'ai_post_analysis_consent_decided_v1': true,
    'ai_post_analysis_consent_v1': true,
  });
  final legacy = PinlogyController(
    store: InMemoryDataStore(),
    deviceLocationService: MockDeviceLocationService(),
    seedIfEmpty: false,
    enablePlatformShare: false,
  );
  await legacy.initialize();
  final recipes = RecipeController(legacy: legacy, store: MemoryRecipeStore());
  await recipes.initialize();
  await recipes.addManualRecipe(
    Recipe(
      sourcePostId: 'manual-test',
      title: '鶏むね肉の照り焼き',
      totalMinutes: 20,
      category: '主菜',
      parts: [
        RecipePart(
          name: '本体',
          ingredients: [
            RecipeIngredient(name: '鶏むね肉', amount: 300, unit: 'g'),
          ],
          steps: [RecipeStep(order: 1, instruction: '鶏肉を焼く')],
        ),
      ],
    ),
  );
  await tester.pumpWidget(
    AppScope(
      controller: legacy,
      child: RecipeScope(controller: recipes, child: const PinlogyApp()),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(recipes.dispose);
  addTearDown(legacy.dispose);
  return (legacy: legacy, recipes: recipes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('白背景の4タブとレシピカードを表示する', (tester) async {
    await pumpRecipeApp(tester);
    expect(find.text('レシピ'), findsWidgets);
    expect(find.text('検索'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('マイページ'), findsOneWidget);
    expect(find.text('鶏むね肉の照り焼き'), findsOneWidget);
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness, Brightness.light);
  });

  testWidgets('カードからレシピ詳細と人数変更を開ける', (tester) async {
    await pumpRecipeApp(tester);
    await tester.tap(find.text('鶏むね肉の照り焼き'));
    await tester.pumpAndSettle();
    expect(find.text('材料'), findsOneWidget);
    expect(find.text('作り方'), findsOneWidget);
    expect(find.text('2人分'), findsOneWidget);
    expect(find.text('料理モードを始める'), findsOneWidget);
  });

  testWidgets('手動レシピに途中から工程を追加できる', (tester) async {
    await pumpRecipeApp(tester);
    await tester.tap(find.byTooltip('レシピを追加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手動で作成'));
    await tester.pumpAndSettle();
    expect(find.text('材料と作り方'), findsOneWidget);
    expect(find.text('工程を追加'), findsOneWidget);
  });
}
