import 'package:flutter/material.dart';

import '../data/ingredient_concern.dart';
import '../recipe_scope.dart';

/// Read settings at display time so existing recipes update without reanalysis.
class IngredientName extends StatelessWidget {
  const IngredientName(this.name, {super.key, this.style});
  final String name;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final settings = RecipeScope.of(context).snapshot.allergySettings;
    final concern = ingredientConcern(name, settings);
    final label = switch (concern) {
      IngredientConcern.allergen => 'アレルギー',
      IngredientConcern.disliked => '苦手',
      IngredientConcern.none => null,
    };
    final color = switch (concern) {
      IngredientConcern.allergen => const Color(0xFFB3261E),
      IngredientConcern.disliked => const Color(0xFF896300),
      IngredientConcern.none => null,
    };
    return Text(
      label == null ? name : '$name（$label）',
      softWrap: true,
      style: color == null
          ? style
          : (style ?? const TextStyle()).copyWith(color: color),
    );
  }
}
