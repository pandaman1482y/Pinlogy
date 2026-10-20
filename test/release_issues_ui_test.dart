import 'package:pinlogy/recipe/data/recipe_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pinlogy/app/pinlogy_controller.dart';
import 'package:pinlogy/models/models.dart';
import 'package:pinlogy/recipe/models/recipe_models.dart';
import 'package:pinlogy/recipe/recipe_controller.dart';
import 'package:pinlogy/recipe/recipe_scope.dart';
import 'package:pinlogy/recipe/ui/ingredient_name.dart';
import 'package:pinlogy/recipe/ui/recipe_ai_page.dart';
import 'package:pinlogy/recipe/ui/recipe_detail_page.dart';

class _CompletedLegacy extends PinlogyController {
  _CompletedLegacy() : super(seedIfEmpty: false, enablePlatformShare: false);
  int recoveries = 0;
  int analyses = 0;
  @override
  Future<void> refreshRemoteAnalyses({String? sourcePostId}) async {
    recoveries++;
  }

  @override
  AnalysisJob? jobForPost(String id) =>
      AnalysisJob(sourcePostId: id, status: AnalysisJobStatus.completed);
  @override
  Future<void> analyzeSharedPost(
    SourcePost post, {
    String? memo,
    List<String>? selectedImagePaths,
  }) async {
    analyses++;
  }
}

class _CompletedRecipes extends RecipeController {
  _CompletedRecipes(PinlogyController legacy) : super(legacy: legacy);
  @override
  Future<void> syncFromIntake() async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('notification refresh only recovers an existing result', () async {
    final legacy = _CompletedLegacy();
    final controller = _CompletedRecipes(legacy);
    await controller.refreshCompletedImport('p');
    expect(legacy.recoveries, 1);
    expect(legacy.analyses, 0);
    controller.dispose();
  });

  testWidgets(
    'previously saved ingredients reflect later settings without reanalysis',
    (tester) async {
      final controller = RecipeController(
        store: _FoodTestStore(),
        legacy: PinlogyController(
          seedIfEmpty: false,
          enablePlatformShare: false,
        ),
      );
      await tester.pumpWidget(
        RecipeScope(
          controller: controller,
          child: const MaterialApp(home: Scaffold(body: IngredientName('長ネギ'))),
        ),
      );
      expect(find.text('長ネギ'), findsOneWidget);
      await controller.updateAllergySettings(
        const AllergySettings(dislikedFoods: ['ねぎ']),
      );
      await tester.pump();
      expect(find.text('長ネギ（苦手）'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('長ネギ（苦手）')).style?.color,
        const Color(0xFF896300),
      );
      await controller.updateAllergySettings(
        const AllergySettings(allergens: ['ねぎ'], dislikedFoods: ['ねぎ']),
      );
      await tester.pump();
      expect(find.text('長ネギ（アレルギー）'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('長ネギ（アレルギー）')).style?.color,
        const Color(0xFFB3261E),
      );
      await controller.updateAllergySettings(const AllergySettings());
      await tester.pump();
      expect(find.text('長ネギ'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'source tag is tappable and an empty nutrition object has an explanation',
    (tester) async {
      final controller = RecipeController(
        store: _FoodTestStore(),
        legacy: PinlogyController(
          seedIfEmpty: false,
          enablePlatformShare: false,
        ),
      );
      controller.snapshot = RecipeSnapshot(
        recipes: [
          Recipe(
            sourcePostId: 'test-source',
            id: 'r',
            title: 'テスト',
            sourceService: 'TikTok',
            sourceUrl: 'https://www.tiktok.com/@a/video/123456789',
            nutrition: const RecipeNutrition(),
          ),
        ],
      );
      await tester.pumpWidget(
        RecipeScope(
          controller: controller,
          child: const MaterialApp(home: RecipeDetailPage(recipeId: 'r')),
        ),
      );
      final ink = find.ancestor(
        of: find.text('TikTok'),
        matching: find.byType(InkWell),
      );
      expect(ink, findsOneWidget);
      expect(tester.widget<InkWell>(ink).onTap, isNotNull);
      await tester.scrollUntilVisible(
        find.text('栄養の目安'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('栄養値は取得できていません'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'AI question loses keyboard focus on submit and has a close control',
    (tester) async {
      final controller = RecipeController(
        store: _FoodTestStore(),
        legacy: PinlogyController(
          seedIfEmpty: false,
          enablePlatformShare: false,
        ),
      );
      await tester.pumpWidget(
        RecipeScope(
          controller: controller,
          child: const MaterialApp(home: RecipeAiPage()),
        ),
      );
      final field = find.byType(TextField);
      await tester.enterText(field, '鶏肉を使いたい');
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      await tester.tap(find.byTooltip('キーボードを閉じる'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
      await tester.tap(field);
      await tester.pump();
      await tester.tap(find.text('提案してもらう'));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.text('AIの回答'), findsOneWidget);
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
