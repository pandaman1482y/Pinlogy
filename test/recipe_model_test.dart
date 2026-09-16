import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/recipe/models/recipe_models.dart';

void main() {
  test('人数変更で数値分量だけを実用的に換算する', () {
    final grams = RecipeIngredient(name: '鶏肉', amount: 300, unit: 'g');
    final spoon = RecipeIngredient(name: '醤油', amount: 1, unit: '大さじ');
    final vague = RecipeIngredient(
      name: '塩',
      originalText: '少々',
      scalable: false,
    );

    expect(grams.quantityFor(1.5), '450g');
    expect(spoon.quantityFor(1.5), '1½大さじ');
    expect(vague.quantityFor(3), '少々');
  });

  test('本体・タレ・出汁を1レシピ内のパートとして保存できる', () {
    final recipe = Recipe(
      sourcePostId: 'post-1',
      title: 'だし巻き卵',
      parts: [
        RecipePart(name: '本体'),
        RecipePart(name: '出汁'),
        RecipePart(name: 'たれ'),
      ],
    );
    final restored = Recipe.fromJson(recipe.toJson());
    expect(restored.parts.map((part) => part.name), ['本体', '出汁', 'たれ']);
  });
}
