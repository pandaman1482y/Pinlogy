import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/recipe/models/recipe_models.dart';
import 'package:pinlogy/recipe/data/recipe_quantity.dart';
import 'package:pinlogy/recipe/data/shopping_list_groups.dart';

void main() {
  test('serving ratios do not truncate thirds and sixths', () {
    expect(scaleRecipeQuantity('300g', 1 / 3), '100g');
    expect(scaleRecipeQuantity('300g', 2 / 3), '200g');
    expect(scaleRecipeQuantity('300g', 1 / 6), '50g');
    expect(scaleRecipeQuantity('1個', 1 / 3), '1/3個');
    expect(scaleRecipeQuantity('1個', 0.333333), '0.333333個');
  });
  test('notes with ranges do not hide structured quantities', () {
    final i = RecipeIngredient(
      name: '鶏肉',
      amount: 250,
      unit: 'g',
      originalText: '鶏肉...250g（下味2〜3分）',
    );
    expect(i.quantityFor(2), '500g（下味2〜3分）');
    expect(i.quantityFor(1), '250g（下味2〜3分）');
    expect(
      RecipeIngredient(
        name: '塩',
        amount: 2,
        unit: 'g',
        originalText: '動画の2〜3秒で確認',
      ).quantityFor(2),
      '4g',
    );
  });
  test('manual lengths and additional count units scale', () {
    for (final pair in {
      '5cm': '10cm',
      '2mm': '4mm',
      '3粒': '6粒',
      '1切れ': '2切れ',
      '1〜2株': '2〜4株',
    }.entries) {
      expect(
        RecipeIngredient(
          name: '材料',
          originalText: pair.key,
          scalable: false,
          userEdited: true,
        ).quantityFor(2),
        pair.value,
      );
    }
    expect(scaleRecipeQuantity('少々', 2), '少々');
    expect(combineShoppingQuantities(['5cm', '5cm']), '10cm');
  });
  test('shopping uses unrounded base and survives save plus resizing', () {
    final ingredient = RecipeIngredient(name: '肉', amount: 103, unit: 'g');
    final recipe = Recipe(
      id: 'r',
      sourcePostId: 'p',
      title: '料理',
      servings: 3,
      parts: [
        RecipePart(name: '材料', ingredients: [ingredient]),
      ],
    );
    var items = addRecipeShoppingItems([], recipe, 1);
    expect(items.single.baseQuantity, '103g');
    expect(items.single.quantity, '103g');
    items = items.map((i) => ShoppingItem.fromJson(i.toJson())).toList();
    items = resizeShoppingRecipe(items, 'r', 6);
    expect(items.single.quantity, ingredient.quantityFor(2));
    expect(items.single.quantity, '206g');
    items = resizeShoppingRecipe(items, 'r', 1);
    expect(items.single.quantity, ingredient.quantityFor(1 / 3));
    items = resizeShoppingRecipe(items, 'r', 3);
    expect(items.single.quantity, '103g');
  });
  test('fixed quantities with numeric amount stay fixed in both views', () {
    final i = RecipeIngredient(
      name: '材料',
      amount: 1,
      unit: '個',
      originalText: '1〜2個',
      scalable: false,
    );
    expect(i.quantityFor(2), '1〜2個');
    final r = Recipe(
      id: 'r',
      sourcePostId: 'p',
      title: '料理',
      servings: 2,
      parts: [
        RecipePart(name: '材料', ingredients: [i]),
      ],
    );
    final saved = addRecipeShoppingItems(
      [],
      r,
      1,
    ).map((i) => ShoppingItem.fromJson(i.toJson())).toList();
    expect(resizeShoppingRecipe(saved, 'r', 4).single.quantity, '1〜2個');
  });
  test('ranges collapse; missing and incompatible units remain safe', () {
    expect(scaleRecipeQuantity('2〜2個', 1), '2個');
    expect(combineShoppingQuantities(['1〜2個', '1〜2個']), '2〜4個');
    expect(combineShoppingQuantities(['', '', '3個', '2個']), '分量記載なし ＋ 5個');
    expect(combineShoppingQuantities(['2個', '3g']), '2個 ＋ 3g');
  });
}
