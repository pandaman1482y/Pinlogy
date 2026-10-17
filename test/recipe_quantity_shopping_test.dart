import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/recipe/data/recipe_quantity.dart';
import 'package:pinlogy/recipe/data/shopping_list_groups.dart';
import 'package:pinlogy/recipe/models/recipe_models.dart';

Recipe _recipe(String id, {String quantity = '1〜2個'}) => Recipe(
  id: id,
  sourcePostId: 'manual-$id',
  title: '料理',
  servings: 2,
  servingUnit: '人分',
  parts: [
    RecipePart(
      name: '材料',
      ingredients: [
        RecipeIngredient(
          name: 'じゃがいも',
          originalText: quantity,
          scalable: false,
        ),
        RecipeIngredient(name: '塩', originalText: '少々', scalable: false),
      ],
    ),
  ],
);

void main() {
  test(
    'manual amounts, fractions and ranges scale; equal endpoints collapse',
    () {
      for (final entry in {
        '250g': '500g',
        '大さじ1/2': '大さじ1',
        '1~2個': '2〜4個',
        '２～２人前': '4人前',
        '1と1/2個': '3個',
      }.entries) {
        expect(
          RecipeIngredient(
            name: '材料',
            originalText: entry.key,
            scalable: false,
          ).quantityFor(2),
          entry.value,
        );
      }
      expect(scaleRecipeQuantity('2〜2人前', 1), '2人前');
      expect(scaleRecipeQuantity('少々', 4), '少々');
      expect(
        RecipeIngredient(
          name: 'じゃがいも',
          amount: 1,
          unit: '個',
          originalText: 'じゃがいも...1〜2個',
        ).quantityFor(2),
        '2〜4個',
      );
    },
  );
  test('ranges and known amounts add while missing quantities occur once', () {
    expect(combineShoppingQuantities(['1~2個', '1〜2個']), '2〜4個');
    expect(combineShoppingQuantities(['1〜2', '1', '2']), '4〜5');
    expect(combineShoppingQuantities(['1〜2個 ＋ 1個', '1〜2個']), '3〜5個');
    expect(combineShoppingQuantities(['', '分量記載なし', '']), '分量記載なし');
    expect(combineShoppingQuantities(['', '3', '分量記載なし', '2']), '分量記載なし ＋ 5');
    expect(combineShoppingQuantities(['大さじ1/3〜1/2', '大さじ1/3〜1/2']), '大さじ2/3〜1');
    expect(combineShoppingQuantities(['0.1g', '0.2g']), '0.3g');
    expect(combineShoppingQuantities(['250g', '1個']), '250g ＋ 1個');
  });
  test(
    'two additions retain batch count and resize from stored base quantities',
    () {
      final r = _recipe('a');
      final items = addRecipeShoppingItems(
        addRecipeShoppingItems([], r, 1),
        r,
        1,
      );
      expect(shoppingBatches(items).length, 2);
      expect(shoppingServings(items), 4);
      expect(shoppingTotalRows(items).first.quantity, '2〜4個');
      final restored = items
          .map((i) => ShoppingItem.fromJson(i.toJson()))
          .toList();
      expect(shoppingBatches(restored).length, 2);
      final smaller = resizeShoppingRecipe(restored, r.id, 2);
      expect(shoppingServings(smaller), 2);
      expect(shoppingTotalRows(smaller).first.quantity, '1〜2個');
      final back = resizeShoppingRecipe(smaller, r.id, 4);
      expect(shoppingTotalRows(back).first.quantity, '2〜4個');
      expect(shoppingBatches(back).length, 2);
      expect(back.map((i) => i.id), items.map((i) => i.id));
    },
  );
  test('other recipes, manual legacy rows and checked state are preserved', () {
    final a = _recipe('a');
    final legacy = ShoppingItem(
      name: '油',
      quantity: '分量記載なし',
      recipeIds: ['a'],
    );
    final items = [
      legacy,
      ...addRecipeShoppingItems([], a, 1).map((i) => i.copyWith(checked: true)),
      ...addRecipeShoppingItems([], _recipe('b'), 1),
    ];
    final updated = resizeShoppingRecipe(items, 'a', 4);
    expect(updated.first, same(legacy));
    expect(updated[1].checked, isTrue);
    expect(updated.last.toJson(), items.last.toJson());
    expect(
      shoppingBatches([
        ShoppingItem.fromJson({
          'name': '古い材料',
          'recipeIds': ['a'],
        }),
      ]),
      isEmpty,
    );
  });
  test('repeated additions combine in both views without losing purchase references', () {
    final r = _recipe('a', quantity: '');
    final items = addRecipeShoppingItems(
      addRecipeShoppingItems([], r, 1),
      r,
      1,
    );
    final group = shoppingRecipeGroups(items, [r]).single;
    expect(shoppingTotalRows(group.items).first.quantity, '分量記載なし');
    expect(shoppingTotalRows(items).first.quantity, '分量記載なし');
    final row = shoppingTotalRows(items).first;
    expect(row.items.length, 2);
    expect(
      shoppingTotalRows([
        row.items.first.copyWith(checked: true),
        row.items.last,
      ]).single.partiallyChecked,
      isTrue,
    );
  });
}
