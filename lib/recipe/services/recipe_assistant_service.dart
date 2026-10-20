import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/recipe_models.dart';
import '../data/ingredient_concern.dart';
import '../../services/ai_analysis_consent.dart';

class RecipeAssistantAnswer {
  const RecipeAssistantAnswer({
    required this.message,
    this.savedRecipeIds = const [],
    this.newSuggestions = const [],
    this.warning,
  });

  final String message;
  final List<String> savedRecipeIds;
  final List<String> newSuggestions;
  final String? warning;
}

class RecipeAssistantService {
  RecipeAssistantService({http.Client? client, String? baseUrl, String? apiKey})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? _url,
      _apiKey = apiKey ?? _key;

  final http.Client _client;
  final String _baseUrl;
  final String _apiKey;

  void dispose() => _client.close();
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _key = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _deviceIdKey = 'ai_quota_device_id_v1';

  bool get configured => _baseUrl.startsWith('https://') && _apiKey.isNotEmpty;

  Future<RecipeAssistantAnswer> ask({
    required String query,
    required List<Recipe> recipes,
    required AllergySettings allergySettings,
  }) async {
    if (!await AiAnalysisConsent().hasConsented()) {
      return RecipeAssistantAnswer(
        message: 'AI解析がオフになっています。AIに質問するには、マイページで「AI解析を利用する」をオンにしてください。',
      );
    }
    final eligible = recipes
        .where((recipe) => !recipeHasFoodConcern(recipe, allergySettings))
        .toList();
    if (!configured) return _localAnswer(query, eligible, allergySettings);
    try {
      final uri = Uri.parse(
        '${_baseUrl.replaceAll(RegExp(r'/$'), '')}/functions/v1/recipe-assistant',
      );
      final preferences = await SharedPreferences.getInstance();
      var deviceId = preferences.getString(_deviceIdKey);
      if (deviceId == null || deviceId.isEmpty) {
        deviceId = const Uuid().v4();
        await preferences.setString(_deviceIdKey, deviceId);
      }
      final response = await _client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'apikey': _apiKey,
              'Content-Type': 'application/json',
              'X-Pinlogy-Device': deviceId,
            },
            body: jsonEncode({
              'query': query,
              'recipes': eligible.take(100).map(_summary).toList(),
              'allergens': allergySettings.allergens,
              'disliked_foods': allergySettings.dislikedFoods,
            }),
          )
          .timeout(const Duration(seconds: 35));
      if (response.statusCode != 200) {
        return _localAnswer(query, eligible, allergySettings);
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map)
        return _localAnswer(query, eligible, allergySettings);
      return RecipeAssistantAnswer(
        message: decoded['message']?.toString() ?? '保存済みレシピから候補を探しました。',
        savedRecipeIds: _strings(
          decoded['saved_recipe_ids'],
        ).where(eligible.map((r) => r.id).toSet().contains).toList(),
        newSuggestions: _strings(decoded['new_suggestions'])
            .where(
              (name) =>
                  ingredientConcern(name, allergySettings) ==
                  IngredientConcern.none,
            )
            .toList(),
        warning: decoded['warning']?.toString(),
      );
    } catch (_) {
      return _localAnswer(query, eligible, allergySettings);
    }
  }

  Map<String, dynamic> _summary(Recipe recipe) => {
    'id': recipe.id,
    'title': recipe.title,
    'description': recipe.description,
    'ingredients': recipe.allIngredients
        .map((item) => item.name)
        .take(30)
        .toList(),
    'category': recipe.category,
    'cuisine': recipe.cuisine,
    'method': recipe.method,
    'total_minutes': recipe.totalMinutes,
    'made_count': recipe.madeCount,
    'last_made_at': recipe.lastMadeAt?.toIso8601String(),
    'allergens': recipe.allergens,
  };

  RecipeAssistantAnswer _localAnswer(
    String query,
    List<Recipe> recipes,
    AllergySettings settings,
  ) {
    final tokens = query
        .toLowerCase()
        .replaceAll(RegExp(r'[これがある最近作ったした動画内容レシピおすすめをでのは？?、,]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.length >= 2)
        .toList();
    final scored =
        recipes
            .where((recipe) => !recipeHasFoodConcern(recipe, settings))
            .map((recipe) {
              final text = [
                recipe.title,
                recipe.description,
                recipe.category,
                recipe.cuisine,
                recipe.mainIngredient,
                recipe.method,
                ...recipe.allIngredients.map((item) => item.name),
              ].whereType<String>().join(' ').toLowerCase();
              var score = tokens.where(text.contains).length * 10;
              if (query.contains('最近') && recipe.lastMadeAt != null) score += 8;
              if (recipe.isFavorite) score += 1;
              return (recipe: recipe, score: score);
            })
            .where((item) => item.score > 0 || tokens.isEmpty)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    final matches = scored.take(5).map((item) => item.recipe.id).toList();
    return RecipeAssistantAnswer(
      message: matches.isEmpty
          ? '登録したアレルギー・苦手な食材を避けて検索しましたが、保存済みレシピに一致する候補がありませんでした。'
          : '保存済みレシピから作りやすそうな候補を選びました。',
      savedRecipeIds: matches,
      newSuggestions: const [],
      warning: settings.allergens.isEmpty
          ? null
          : '登録された材料名とアレルゲン情報に基づいて候補を除外しています。原材料の抽出漏れや混入までは判定できないため、元投稿と商品表示も確認してください。',
    );
  }
}

List<String> _strings(dynamic value) => value is List
    ? value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList()
    : const [];
