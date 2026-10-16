import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/recipe/data/shopping_list_groups.dart';
import 'package:pinlogy/recipe/models/recipe_models.dart';
import 'package:pinlogy/recipe/ui/shopping_list_page.dart';

Recipe recipe(String id, String title, double grams) => Recipe(
  id: id,
  sourcePostId: 'p$id',
  title: title,
  parts: [
    RecipePart(
      name: '本体',
      ingredients: [RecipeIngredient(name: '鶏肉', amount: grams, unit: 'g')],
    ),
  ],
);
void main() {
  test('same ingredient remains separate per recipe and totals once', () {
    final first = recipe('a', '親子丼', 250);
    final second = recipe('b', '唐揚げ', 100);
    final items = addRecipeShoppingItems(
      addRecipeShoppingItems([], first, 1),
      second,
      1,
    );
    expect(items.length, 2);
    final groups = shoppingRecipeGroups(items, [first, second]);
    expect(groups.map((group) => group.title), ['親子丼', '唐揚げ']);
    expect(groups[0].items.single.quantity, '250g');
    expect(groups[1].items.single.quantity, '100g');
    final totals = shoppingTotalRows(items);
    expect(totals.length, 1);
    expect(totals.single.quantity, '350g');
    expect(totals.single.items.length, 2);
  });
  test(
    'decimal and fraction sums are exact; ranges and incompatible units stay separate',
    () {
      expect(combineShoppingQuantities(['0.1g', '0.2g']), '0.3g');
      expect(combineShoppingQuantities(['大さじ1/2', '大さじ1/2']), '大さじ1');
      expect(combineShoppingQuantities(['小さじ1/3', '小さじ1/3']), '小さじ2/3');
      expect(combineShoppingQuantities(['大さじ１', '大さじ2']), '大さじ3');
      expect(combineShoppingQuantities(['250g', '1個']), '250g ＋ 1個');
      expect(combineShoppingQuantities(['1〜2個', '少々']), '1〜2個 ＋ 少々');
      expect(combineShoppingQuantities(['250g', '']), '250g ＋ 分量記載なし');
      expect(combineShoppingQuantities(['1/0個', '1個']), '1/0個 ＋ 1個');
    },
  );
  test('legacy shared entries are not split, lost or counted twice', () {
    final old = ShoppingItem(
      id: 'old',
      name: '鶏肉',
      quantity: '250g + 100g',
      recipeIds: ['a', 'b'],
    );
    final added = addRecipeShoppingItems([old], recipe('c', 'カレー', 50), 1);
    expect(added.length, 2);
    final groups = shoppingRecipeGroups(added, []);
    expect(groups.first.title, '複数の料理分');
    expect(groups.first.items.single.id, 'old');
    expect(shoppingTotalRows(added).single.items.length, 2);
  });
  test(
    'partial purchase state uses shared source items without resetting checked rows',
    () {
      final items = [
        ShoppingItem(name: '塩', quantity: '1g', checked: true),
        ShoppingItem(name: '塩', quantity: '2g'),
      ];
      final total = shoppingTotalRows(items).single;
      expect(total.partiallyChecked, isTrue);
      expect(total.checked, isFalse);
      final checked = items
          .map((item) => item.copyWith(checked: true))
          .toList();
      expect(shoppingTotalRows(checked).single.checked, isTrue);
      final a = recipe('a', '料理', 100);
      final initial = addRecipeShoppingItems(
        [],
        a,
        1,
      ).single.copyWith(checked: true);
      expect(addRecipeShoppingItems([initial], a, 1).length, 2);
    },
  );
  test('manual rows have their own group', () {
    final groups = shoppingRecipeGroups([ShoppingItem(name: '牛乳')], []);
    expect(groups.single.title, 'その他の買うもの');
  });
  testWidgets('add dialog validates and returns entered values', (
    tester,
  ) async {
    ShoppingItem? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showAddShoppingItemDialog(context);
              },
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();
    expect(find.text('品名を入力してください'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('shopping_name')), ' 牛乳 ');
    await tester.enterText(
      find.byKey(const ValueKey('shopping_quantity')),
      ' 500ml ',
    );
    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();
    expect(result?.name, '牛乳');
    expect(result?.quantity, '500ml');
    expect(result?.recipeIds, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('cancel does not add anything', (tester) async {
    ShoppingItem? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showAddShoppingItemDialog(context);
              },
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
