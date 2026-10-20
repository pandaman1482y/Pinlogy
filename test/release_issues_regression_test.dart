import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pinlogy/services/ai_analysis_consent.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pinlogy/models/models.dart';
import 'package:pinlogy/recipe/data/ingredient_concern.dart';
import 'package:pinlogy/recipe/data/recipe_sync_policy.dart';
import 'package:pinlogy/recipe/models/recipe_models.dart';
import 'package:pinlogy/recipe/services/recipe_assistant_service.dart';
import 'package:pinlogy/services/ai_post_analysis_service.dart';
import 'package:pinlogy/services/location_services.dart';

class _CountingFallback implements PostAnalysisService {
  int calls = 0;
  @override
  Future<PostAnalysisResponse> analyze(PostAnalysisRequest request) async {
    calls++;
    return PostAnalysisResponse(
      sourcePostId: request.sourcePostId,
      candidates: const [],
      rawSummary: '',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'iOS consent updates only the analysis flag, preserving other share settings',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const channel = MethodChannel('com.pinlogy/share');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = null;
      });
      final consent = AiAnalysisConsent();
      await consent.setConsented(true);
      await consent.setConsented(false);
      expect(calls.map((call) => call.arguments).toList(), [
        {'aiAnalysisEnabled': true},
        {'aiAnalysisEnabled': false},
      ]);
      expect(await consent.hasConsented(), isFalse);
    },
  );

  test('allergy takes precedence, kana and common names match', () {
    const settings = AllergySettings(
      allergens: ['卵', 'えび', '乳'],
      dislikedFoods: ['卵', 'ねぎ'],
    );
    expect(ingredientConcern('玉子', settings), IngredientConcern.allergen);
    expect(ingredientConcern('冷凍エビ', settings), IngredientConcern.allergen);
    expect(ingredientConcern('牛乳', settings), IngredientConcern.allergen);
    expect(ingredientConcern('長ネギ', settings), IngredientConcern.disliked);
    expect(ingredientConcern('豆乳', settings), IngredientConcern.none);
    expect(ingredientConcern('乳化剤', settings), IngredientConcern.none);
    expect(ingredientConcern('鶏肉', settings), IngredientConcern.none);
    expect(
      ingredientConcern('タマネギ', const AllergySettings(dislikedFoods: ['玉ねぎ'])),
      IngredientConcern.disliked,
    );
    expect(
      ingredientConcern('鶏肉', const AllergySettings(allergens: [' '])),
      IngredientConcern.none,
    );
  });

  test('nutrition reads both server and saved keys and retains its basis', () {
    final nutrition = RecipeNutrition.fromJson({
      'calories': '500',
      'protein_grams': 20,
      'fat_grams': 10.5,
      'carbohydrate_grams': 65,
      'basis': 'recipe_total',
    });
    expect(nutrition.hasValues, isTrue);
    expect(nutrition.calories, 500);
    expect(nutrition.proteinGrams, 20);
    final restored = RecipeNutrition.fromJson(nutrition.toJson());
    expect(restored.toJson(), nutrition.toJson());
    expect(
      RecipeNutrition.fromJson({
        'calories': -1,
        'protein_grams': 'NaN',
      }).hasValues,
      isFalse,
    );
    expect(RecipeNutrition.fromJson({}).hasValues, isFalse);
    expect(RecipeNutrition.fromJson({'calories': 300}).basis, isNull);
  });

  test('a stale remote processing entry cannot override local completion', () {
    final now = DateTime.now();
    expect(
      shouldShowImportInSession(
        status: RecipeImportStatus.analyzing,
        updatedAt: now,
        sessionStartedAt: now,
        remoteActive: true,
        localTerminal: true,
      ),
      isFalse,
    );
    expect(
      shouldShowImportInSession(
        status: RecipeImportStatus.awaitingSelection,
        updatedAt: now,
        sessionStartedAt: now,
        remoteActive: true,
        localTerminal: true,
      ),
      isTrue,
    );
  });

  test('AI OFF never runs local OCR or sends a new analysis request', () async {
    final fallback = _CountingFallback();
    var requests = 0;
    final service = AiPostAnalysisService(
      fallback: fallback,
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      service.analyze(
        PostAnalysisRequest(
          sourcePostId: 'p',
          url: 'https://www.tiktok.com/@a/video/123456789',
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('AI解析がオフ'),
        ),
      ),
    );
    expect(fallback.calls, 0);
    expect(requests, 0);
  });

  test('AI tab does not send recipe data while consent is OFF', () async {
    var requests = 0;
    final service = RecipeAssistantService(
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    final answer = await service.ask(
      query: '鶏肉',
      recipes: [],
      allergySettings: const AllergySettings(),
    );
    expect(answer.message, contains('AI解析がオフ'));
    expect(requests, 0);
  });
}
