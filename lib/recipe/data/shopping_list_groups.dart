import '../models/recipe_models.dart';
import 'recipe_quantity.dart';
export 'recipe_quantity.dart' show combineShoppingQuantities;

class ShoppingRecipeGroup {
  ShoppingRecipeGroup(this.id, this.title);
  final String id;
  final String title;
  final List<ShoppingItem> items = [];
  String? get recipeId => id.startsWith('recipe:') ? id.substring(7) : null;
}

List<ShoppingRecipeGroup> shoppingRecipeGroups(
  List<ShoppingItem> items,
  List<Recipe> recipes,
) {
  final titles = {for (final recipe in recipes) recipe.id: recipe.title};
  final groups = <String, ShoppingRecipeGroup>{};
  for (final item in items) {
    final id = item.recipeIds.length == 1
        ? 'recipe:${item.recipeIds.single}'
        : item.recipeIds.isEmpty
        ? 'manual'
        : 'shared';
    final title = item.recipeIds.length == 1
        ? titles[item.recipeIds.single] ?? '元の料理が削除された項目'
        : item.recipeIds.isEmpty
        ? 'その他の買うもの'
        : '複数の料理分';
    (groups[id] ??= ShoppingRecipeGroup(id, title)).items.add(item);
  }
  return groups.values.toList();
}

class ShoppingTotalRow {
  ShoppingTotalRow(this.name);
  final String name;
  final List<ShoppingItem> items = [];
  bool get checked => items.every((item) => item.checked);
  bool get partiallyChecked => !checked && items.any((item) => item.checked);
  String get quantity =>
      combineShoppingQuantities(items.map((item) => item.quantity));
}

List<ShoppingTotalRow> shoppingTotalRows(List<ShoppingItem> items) {
  final rows = <String, ShoppingTotalRow>{};
  for (final item in items) {
    final key = item.name.trim().toLowerCase();
    (rows[key] ??= ShoppingTotalRow(item.name)).items.add(item);
  }
  return rows.values.toList();
}

/// New entries retain recipe ownership; legacy combined entries remain untouched.
List<ShoppingItem> addRecipeShoppingItems(
  List<ShoppingItem> existing,
  Recipe recipe,
  double multiplier,
) {
  if (!multiplier.isFinite || multiplier <= 0) return List.of(existing);
  final batch = newShoppingBatchId();
  return [
    ...existing,
    for (final ingredient in recipe.allIngredients)
      ShoppingItem(
        name: ingredient.name,
        quantity: ingredient.quantityFor(multiplier),
        recipeIds: [recipe.id],
        batchId: batch,
        baseQuantity: ingredient.calculationQuantity,
        quantityCanScale: ingredient.quantityCanScale,
        batchServings: (recipe.servings > 0 ? recipe.servings : 1) * multiplier,
        quantityMultiplier: multiplier,
      ),
  ];
}

String newShoppingBatchId() => ShoppingItem(name: '').id;

Map<String, double> shoppingBatches(Iterable<ShoppingItem> items) => {
  for (final item in items)
    if (item.batchId != null && item.batchServings != null)
      item.batchId!: item.batchServings!,
};

double shoppingServings(Iterable<ShoppingItem> items) =>
    shoppingBatches(items).values.fold(0.0, (a, b) => a + b);

List<ShoppingItem> resizeShoppingRecipe(
  List<ShoppingItem> items,
  String recipeId,
  double servings,
) {
  final selected = items.where(
    (i) =>
        i.recipeIds.length == 1 &&
        i.recipeIds.single == recipeId &&
        i.batchId != null,
  );
  final current = shoppingServings(selected);
  if (current <= 0 || !servings.isFinite || servings <= 0) return items;
  final ratio = servings / current;
  return [
    for (final item in items)
      if (selected.contains(item) && item.baseQuantity != null)
        item.copyWith(
          quantity: scaleRecipeQuantity(
            item.baseQuantity!,
            item.quantityCanScale == false
                ? 1
                : item.quantityMultiplier * ratio,
          ),
          quantityMultiplier: item.quantityMultiplier * ratio,
          batchServings: item.batchServings! * ratio,
        )
      else
        item,
  ];
}
