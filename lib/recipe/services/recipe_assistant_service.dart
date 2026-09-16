import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/recipe_models.dart';

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
  RecipeAssistantService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _key = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _deviceIdKey = 'ai_quota_device_id_v1';

  bool get configured => _url.startsWith('https://') && _key.isNotEmpty;

  Future<RecipeAssistantAnswer> ask({
    required String query,
    required List<Recipe> recipes,
    required AllergySettings allergySettings,
  }) async {
    if (!configured) return _localAnswer(query, recipes, allergySettings);
    try {
      final uri = Uri.parse(
        '${_url.replaceAll(RegExp(r'/$'), '')}/functions/v1/recipe-assistant',
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
              'Authorization': 'Bearer $_key',
              'apikey': _key,
              'Content-Type': 'application/json',
              'X-Pinlogy-Device': deviceId,
            },
            body: jsonEncode({
              'query': query,
              'recipes': recipes.take(100).map(_summary).toList(),
              'allergens': allergySettings.allergens,
              'disliked_foods': allergySettings.dislikedFoods,
            }),
          )
          .timeout(const Duration(seconds: 35));
      if (response.statusCode != 200) {
        return _localAnswer(query, recipes, allergySettings);
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return _localAnswer(query, recipes, allergySettings);
      return RecipeAssistantAnswer(
        message: decoded['message']?.toString() ?? '保存済みレシピから候補を探しました。',
        savedRecipeIds: _strings(decoded['saved_recipe_ids']),
        newSuggestions: _strings(decoded['new_suggestions']),
        warning: decoded['warning']?.toString(),
      );
    } catch (_) {
      return _localAnswer(query, recipes, allergySettings);
    }
  }

  Map<String, dynamic> _summary(Recipe recipe) => {
    'id': recipe.id,
    'title': recipe.title,
    'description': recipe.description,
    'ingredients': recipe.allIngredients.map((item) => item.name).take(30).toList(),
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
    final scored = recipes.map((recipe) {
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
    }).where((item) => item.score > 0 || tokens.isEmpty).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    final matches = scored.take(5).map((item) => item.recipe.id).toList();
    return RecipeAssistantAnswer(
      message: matches.isEmpty
          ? '保存済みレシピには一致するものがありませんでした。'
          : '保存済みレシピから作りやすそうな候補を選びました。',
      savedRecipeIds: matches,
      newSuggestions: matches.isEmpty ? ['材料を少し変えた主菜', '手早く作れる副菜'] : const [],
      warning: settings.allergens.isEmpty
          ? null
          : 'アレルギー設定を考慮しましたが、安全を保証するものではありません。',
    );
  }
}

List<String> _strings(dynamic value) => value is List
    ? value.map((item) => item.toString()).where((item) => item.isNotEmpty).toList()
    : const [];
