import '../models/recipe_models.dart';

class ShoppingRecipeGroup {
  ShoppingRecipeGroup(this.id, this.title);
  final String id;
  final String title;
  final List<ShoppingItem> items = [];
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
  final items = List<ShoppingItem>.of(existing);
  for (final ingredient in recipe.allIngredients) {
    final quantity = ingredient.quantityFor(multiplier);
    final index = items.indexWhere(
      (item) =>
          !item.checked &&
          item.recipeIds.length == 1 &&
          item.recipeIds.single == recipe.id &&
          item.name.trim().toLowerCase() ==
              ingredient.name.trim().toLowerCase(),
    );
    if (index < 0) {
      items.add(
        ShoppingItem(
          name: ingredient.name,
          quantity: quantity,
          recipeIds: [recipe.id],
        ),
      );
    } else {
      items[index] = items[index].copyWith(
        quantity: combineShoppingQuantities([items[index].quantity, quantity]),
      );
    }
  }
  return items;
}

class _Quantity {
  _Quantity(this.numerator, this.denominator, this.unit, this.prefix);
  final BigInt numerator, denominator;
  final String unit;
  final bool prefix;
}

_Quantity? _parseQuantity(String source) {
  final value = source
      .trim()
      .replaceAllMapped(
        RegExp('[０-９]'),
        (match) => String.fromCharCode(match[0]!.codeUnitAt(0) - 0xfee0),
      )
      .replaceAll('．', '.')
      .replaceAll('／', '/');
  const number = r'(\d+(?:\.\d+)?|\d+\s*/\s*\d+)';
  final prefix = RegExp('^(大さじ|小さじ|カップ)\\s*$number\$').firstMatch(value);
  final suffix = RegExp(
    '^$number\\s*(kg|mg|g|ml|mL|L|個|本|枚|束|袋|片|缶|パック|玉|丁|合)\$',
  ).firstMatch(value);
  if (prefix == null && suffix == null) return null;
  final raw = (prefix != null ? prefix[2]! : suffix![1]!).replaceAll(
    RegExp(r'\s+'),
    '',
  );
  final unit = (prefix != null ? prefix[1]! : suffix![2]!).replaceAll(
    'mL',
    'ml',
  );
  if (raw.length > 30) return null;
  BigInt n, d;
  if (raw.contains('/')) {
    final values = raw.split('/');
    n = BigInt.parse(values[0]);
    d = BigInt.parse(values[1]);
    if (d == BigInt.zero) return null;
  } else if (raw.contains('.')) {
    final values = raw.split('.');
    d = BigInt.one;
    for (var i = 0; i < values[1].length; i++) {
      d *= BigInt.from(10);
    }
    n = BigInt.parse(values[0]) * d + BigInt.parse(values[1]);
  } else {
    n = BigInt.parse(raw);
    d = BigInt.one;
  }
  return _Quantity(n, d, unit, prefix != null);
}

String _formatFraction(BigInt numerator, BigInt denominator) {
  final gcd = numerator.gcd(denominator);
  final n = numerator ~/ gcd, d = denominator ~/ gcd;
  if (d == BigInt.one) return '$n';
  var remaining = d;
  while (remaining % BigInt.two == BigInt.zero) {
    remaining ~/= BigInt.two;
  }
  while (remaining % BigInt.from(5) == BigInt.zero) {
    remaining ~/= BigInt.from(5);
  }
  if (remaining != BigInt.one) return '$n/$d';
  // Render terminating decimals with integer arithmetic, never rounding quantities.
  final whole = n ~/ d;
  var remainder = n % d;
  final decimals = StringBuffer();
  while (remainder != BigInt.zero) {
    remainder *= BigInt.from(10);
    decimals.write(remainder ~/ d);
    remainder %= d;
  }
  return '$whole.$decimals';
}

/// Only explicit numbers with the same unit are added. No unit conversions or estimates.
String combineShoppingQuantities(Iterable<String> quantities) {
  final values = quantities.map((value) => value.trim()).toList();
  if (values.length == 1) return values.single;
  final groups = <String, List<String>>{};
  var unknown = 0;
  for (final value in values) {
    final parsed = _parseQuantity(value);
    final key = parsed == null
        ? 'text:${unknown++}'
        : '${parsed.prefix}:${parsed.unit}';
    (groups[key] ??= []).add(value.isEmpty ? '分量記載なし' : value);
  }
  final output = <String>[];
  for (final group in groups.values) {
    final first = _parseQuantity(group.first);
    if (group.length == 1 || first == null) {
      output.add(group.first);
      continue;
    }
    var n = BigInt.zero, d = BigInt.one;
    for (final value in group) {
      final parsed = _parseQuantity(value)!;
      n = n * parsed.denominator + parsed.numerator * d;
      d *= parsed.denominator;
      final gcd = n.gcd(d);
      n ~/= gcd;
      d ~/= gcd;
    }
    final amount = _formatFraction(n, d);
    output.add(first.prefix ? '${first.unit}$amount' : '$amount${first.unit}');
  }
  return output.join(' ＋ ');
}
