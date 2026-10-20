import 'package:pinlogy/recipe/data/recipe_store.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pinlogy/app/pinlogy_controller.dart';
import 'package:pinlogy/recipe/data/ingredient_concern.dart';
import 'package:pinlogy/recipe/models/recipe_models.dart';
import 'package:pinlogy/recipe/recipe_controller.dart';
import 'package:pinlogy/recipe/recipe_scope.dart';
import 'package:pinlogy/recipe/services/recipe_assistant_service.dart';
import 'package:pinlogy/recipe/ui/food_tag_editor.dart';
import 'package:pinlogy/recipe/ui/recipe_ai_page.dart';
import 'package:pinlogy/recipe/ui/recipe_profile_page.dart';

class _LongAnswer extends RecipeAssistantService {
  @override
  Future<RecipeAssistantAnswer> ask({
    required String query,
    required List<Recipe> recipes,
    required AllergySettings allergySettings,
  }) async =>
      RecipeAssistantAnswer(message: List.filled(60, '料理の回答です。').join('\n'));
}

Recipe _recipe(String id, String ingredient) => Recipe(
  sourcePostId: 'test-source',
  id: id,
  title: id,
  parts: [
    RecipePart(
      name: '主菜',
      ingredients: [RecipeIngredient(name: ingredient)],
    ),
  ],
);
RecipeController _controller() => RecipeController(
  store: _FoodTestStore(),
  legacy: PinlogyController(seedIfEmpty: false, enablePlatformShare: false),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'ai_post_analysis_consent_v1': true,
    }),
  );

  test(
    'general chicken preference includes its cuts but not unrelated foods',
    () {
      const settings = AllergySettings(dislikedFoods: ['鶏肉']);
      for (final name in ['鶏胸肉', '鶏むね肉', '鶏もも肉', '鶏ひき肉', 'ささみ', 'チキン']) {
        expect(
          ingredientConcern(name, settings),
          IngredientConcern.disliked,
          reason: name,
        );
      }
      expect(ingredientConcern('牛乳', settings), IngredientConcern.none);
      expect(ingredientConcern('豚肉', settings), IngredientConcern.none);
      expect(recipeHasFoodConcern(_recipe('chicken', '鶏胸肉'), settings), isTrue);
    },
  );

  test('food entries split and deduplicate multiple values', () {
    expect(splitFoodEntries(' 鶏肉、パクチー\nレバー,鶏肉；えび '), [
      '鶏肉',
      'パクチー',
      'レバー',
      'えび',
    ]);
  });

  test(
    'online candidates are filtered before sending and after AI response',
    () async {
      Map? sent;
      final service = RecipeAssistantService(
        baseUrl: 'https://example.invalid',
        apiKey: 'test',
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map;
          return http.Response(
            jsonEncode({
              'message': '候補です',
              'saved_recipe_ids': ['chicken', 'egg', 'tofu', 'invented'],
              'new_suggestions': ['鶏胸肉のソテー', '豆腐の冷奴'],
              'warning': null,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final answer = await service.ask(
        query: '主菜',
        recipes: [
          _recipe('chicken', '鶏胸肉'),
          _recipe('egg', '玉子'),
          _recipe('tofu', '豆腐'),
        ],
        allergySettings: const AllergySettings(
          allergens: ['卵'],
          dislikedFoods: ['鶏肉'],
        ),
      );
      expect((sent!['recipes'] as List).map((r) => r['id']).toList(), ['tofu']);
      expect(answer.savedRecipeIds, ['tofu']);
      expect(answer.newSuggestions, ['豆腐の冷奴']);
      service.dispose();
    },
  );

  test(
    'network failure fallback also excludes registered ingredients',
    () async {
      final service = RecipeAssistantService(
        baseUrl: 'https://example.invalid',
        apiKey: 'test',
        client: MockClient((_) async => http.Response('offline', 503)),
      );
      final answer = await service.ask(
        query: '',
        recipes: [_recipe('chicken', '鶏胸肉'), _recipe('tofu', '豆腐')],
        allergySettings: const AllergySettings(dislikedFoods: ['鶏肉']),
      );
      expect(answer.savedRecipeIds, ['tofu']);
      service.dispose();
    },
  );

  test('partial nutrition and excluded ingredients survive save/load', () {
    final value = RecipeNutrition.fromJson({
      'calories': 300,
      'basis': 'known_ingredients_total',
      'excluded_ingredients': ['オリーブオイル', '塩'],
    });
    expect(value.isPartial, isTrue);
    expect(value.hasValues, isTrue);
    expect(RecipeNutrition.fromJson(value.toJson()).excludedIngredients, [
      'オリーブオイル',
      '塩',
    ]);
  });

  testWidgets(
    'allergen selection keeps every item in the same row and position',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _controller();
      await tester.pumpWidget(
        RecipeScope(
          controller: controller,
          child: const MaterialApp(home: AllergySettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      const names = ['卵', '乳', '小麦', 'えび', 'かに', 'そば', '落花生', 'くるみ'];
      final positions = {
        for (final name in names)
          name: tester.getRect(find.byKey(ValueKey('allergen_$name'))),
      };
      for (final name in names) {
        await tester.tap(find.byKey(ValueKey('allergen_$name')));
        await tester.pump();
      }
      for (final name in names) {
        expect(
          tester.getRect(find.byKey(ValueKey('allergen_$name'))),
          positions[name],
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('multiple custom entries can be added and removed individually', (
    tester,
  ) async {
    final input = TextEditingController();
    var values = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FoodTagEditor(
              controller: input,
              values: values,
              label: '苦手な食材',
              fieldKey: 'foods',
              onChanged: (next) => setState(() => values = next),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('foods')), '鶏肉、レバー');
    await tester.tap(find.byKey(const ValueKey('foods_add')));
    await tester.pump();
    expect(values, ['鶏肉', 'レバー']);
    await tester.enterText(find.byKey(const ValueKey('foods')), 'パクチー');
    await tester.tap(find.byKey(const ValueKey('foods_add')));
    await tester.pump();
    expect(values, ['鶏肉', 'レバー', 'パクチー']);
    tester
        .widget<InputChip>(find.widgetWithText(InputChip, 'レバー'))
        .onDeleted!();
    await tester.pump();
    expect(values, ['鶏肉', 'パクチー']);
    await tester.pumpWidget(const SizedBox());
    input.dispose();
  });

  testWidgets('custom lists and an unsubmitted draft are saved and restored', (
    tester,
  ) async {
    final controller = _controller();
    await tester.pumpWidget(
      RecipeScope(
        controller: controller,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AllergySettingsPage(),
                  ),
                ),
                child: const Text('設定を開く'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('設定を開く'));
    await tester.pumpAndSettle();
    final other = find.byKey(const ValueKey('other_allergens'));
    await tester.scrollUntilVisible(
      other,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(other, '大豆、山芋');
    await tester.tap(find.byKey(const ValueKey('other_allergens_add')));
    await tester.pump();
    final disliked = find.byKey(const ValueKey('disliked_foods'));
    await tester.scrollUntilVisible(
      disliked,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(disliked, '鶏肉');
    await tester.tap(find.byKey(const ValueKey('disliked_foods_add')));
    await tester.pump();
    await tester.enterText(disliked, 'パクチー');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(controller.snapshot.allergySettings.allergens, ['大豆', '山芋']);
    expect(controller.snapshot.allergySettings.dislikedFoods, ['鶏肉', 'パクチー']);
    await tester.tap(find.text('設定を開く'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('パクチー'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.widgetWithText(InputChip, 'パクチー'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'long answers scroll independently while the question stays visible',
    (tester) async {
      final controller = _controller();
      await tester.pumpWidget(
        RecipeScope(
          controller: controller,
          child: MaterialApp(home: RecipeAiPage(assistant: _LongAnswer())),
        ),
      );
      final field = find.byKey(const ValueKey('ai_query_input'));
      await tester.enterText(field, '何が作れる？');
      await tester.tap(find.byTooltip('質問を送信'));
      await tester.pumpAndSettle();
      final position = tester.getRect(field);
      await tester.drag(
        find.byKey(const ValueKey('ai_answer_list')),
        const Offset(0, -350),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(field), position);
      expect(tester.widget<TextField>(field).controller!.text, '何が作れる？');
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}

// These UI tests must not depend on platform file I/O.
class _FoodTestStore implements RecipeStore {
  final Map<String, RecipeSnapshot> _values = {};
  @override
  Future<RecipeSnapshot> load({
    String? ownerId,
    bool migrateLegacy = false,
  }) async => _values[ownerId ?? 'guest'] ?? RecipeSnapshot();
  @override
  Future<void> save(RecipeSnapshot snapshot, {String? ownerId}) async {
    _values[ownerId ?? 'guest'] = RecipeSnapshot.fromJson(snapshot.toJson());
  }

  @override
  Future<void> clear({String? ownerId}) async {
    _values.remove(ownerId ?? 'guest');
  }
}
