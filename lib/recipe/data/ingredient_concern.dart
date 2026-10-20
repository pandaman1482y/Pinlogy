import '../models/recipe_models.dart';

enum IngredientConcern { none, disliked, allergen }

/// A display aid based on ingredient names, not a complete allergen detector.
IngredientConcern ingredientConcern(String name, AllergySettings settings) {
  final text = _normalize(name);
  bool matches(String value) {
    final key = _normalize(value);
    if (key.isEmpty) return false;
    final aliases = _aliases[key];
    return (aliases ?? [key]).any(text.contains);
  }

  if (settings.allergens.any(matches)) return IngredientConcern.allergen;
  if (settings.dislikedFoods.any(matches)) return IngredientConcern.disliked;
  return IngredientConcern.none;
}

String _normalize(String value) => String.fromCharCodes(
  value.trim().toLowerCase().runes.map(
    (code) => code >= 0x30a1 && code <= 0x30f6 ? code - 0x60 : code,
  ),
).replaceAll(RegExp(r'[\s　]+'), '');

const _aliases = <String, List<String>>{
  '鶏肉': ['鶏', 'とり肉', 'とりにく', 'ちきん', 'ささみ', '若どり'],
  'とりにく': ['鶏', 'とり肉', 'とりにく', 'ちきん', 'ささみ', '若どり'],
  'ちきん': ['鶏', 'とり肉', 'とりにく', 'ちきん', 'ささみ', '若どり'],
  '鶏胸肉': ['鶏胸', '鶏むね', 'とりむね'],
  '鶏むね肉': ['鶏胸', '鶏むね', 'とりむね'],
  '豚肉': ['豚', 'ぶた肉', 'ぶたにく', 'ぽーく'],
  '卵': ['卵', '玉子', 'たまご'],
  '乳': ['牛乳', '乳製品', '粉乳', '練乳', '生くりーむ', 'ばたー', 'ちーず', 'よーぐると', 'みるく'],
  '小麦': ['小麦', '薄力粉', '強力粉', '中力粉', 'ぱん粉', 'うどん', 'ぱすた', 'すぱげってぃ'],
  'えび': ['えび', '海老', '蝦'],
  'かに': ['かに', '蟹'],
  'そば': ['そば', '蕎麦'],
  '落花生': ['落花生', 'ぴーなっつ'],
  'くるみ': ['くるみ', '胡桃'],
  'ねぎ': ['ねぎ', '葱'],
  '玉ねぎ': ['玉ねぎ', '玉葱', 'たまねぎ'],
  'たまねぎ': ['玉ねぎ', '玉葱', 'たまねぎ'],
  'にんじん': ['にんじん', '人参'],
  '人参': ['にんじん', '人参'],
};

/// Used by both online suggestions and the local fallback.
bool recipeHasFoodConcern(Recipe recipe, AllergySettings settings) =>
    recipe.allIngredients.any(
      (item) =>
          ingredientConcern(item.name, settings) != IngredientConcern.none,
    ) ||
    recipe.allergens.any(
      (name) =>
          ingredientConcern(
            name,
            AllergySettings(allergens: settings.allergens),
          ) ==
          IngredientConcern.allergen,
    );
