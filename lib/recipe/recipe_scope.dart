import 'package:flutter/widgets.dart';

import 'recipe_controller.dart';

class RecipeScope extends InheritedNotifier<RecipeController> {
  const RecipeScope({
    super.key,
    required RecipeController controller,
    required super.child,
  }) : super(notifier: controller);

  static RecipeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RecipeScope>();
    assert(scope != null, 'RecipeScope が見つかりません');
    return scope!.notifier!;
  }

  static RecipeController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<RecipeScope>();
    assert(scope != null, 'RecipeScope が見つかりません');
    return scope!.notifier!;
  }
}
