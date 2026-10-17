import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../data/shopping_list_groups.dart';
import '../models/recipe_models.dart';
import '../recipe_scope.dart';
import 'recipe_widgets.dart';

class ShoppingListPage extends StatefulWidget {
  const ShoppingListPage({super.key});
  @override
  State<ShoppingListPage> createState() => _ShoppingListPageState();
}

class _ShoppingListPageState extends State<ShoppingListPage> {
  bool _combined = false;

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('買い物リストを保存できませんでした。もう一度お試しください。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = RecipeScope.of(context);
    final items = controller.snapshot.shoppingItems;
    final recipes = controller.snapshot.recipes;
    final groups = shoppingRecipeGroups(items, recipes);
    final totals = shoppingTotalRows(items);
    final displayedRows = _combined
        ? totals
        : [for (final group in groups) ...shoppingTotalRows(group.items)];
    final checked = displayedRows.where((row) => row.checked).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('買い物リスト'),
        actions: [
          if (items.any((item) => item.checked))
            TextButton(
              onPressed: () => _perform(controller.clearPurchasedItems),
              child: const Text('購入済みを削除'),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        tooltip: '買うものを追加',
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('買うものを追加'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('料理ごと'),
                      icon: Icon(Icons.restaurant_menu_rounded),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('全部まとめて'),
                      icon: Icon(Icons.view_list_rounded),
                    ),
                  ],
                  selected: {_combined},
                  showSelectedIcon: false,
                  onSelectionChanged: (values) =>
                      setState(() => _combined = values.single),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '未購入 ${displayedRows.length - checked}件',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      '購入済み $checked件',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: displayedRows.isEmpty
                        ? 0
                        : checked / displayedRows.length,
                    minHeight: 5,
                    backgroundColor: mint,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shopping_basket_outlined,
                            color: mossDeep,
                            size: 46,
                          ),
                          SizedBox(height: 16),
                          Text('買うものはまだありません'),
                          SizedBox(height: 8),
                          Text(
                            'レシピの材料や、買っておきたいものを追加しましょう。',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: secondaryInk),
                          ),
                        ],
                      ),
                    ),
                  )
                : _combined
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                    key: const PageStorageKey('shopping_combined'),
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          '同じ材料をまとめて表示。同じ単位の分量だけを合計します。',
                          style: TextStyle(fontSize: 12, color: secondaryInk),
                        ),
                      ),
                      for (final row in totals)
                        _ShoppingTile(
                          key: ValueKey(row.name),
                          name: row.name,
                          quantity: row.quantity,
                          checked: row.checked,
                          partial: row.partiallyChecked,
                          caption: _sourceLabels(row.items, recipes),
                          onChanged: () => _perform(
                            () => controller.setShoppingItemsChecked(
                              row.items.map((item) => item.id),
                              !row.checked,
                            ),
                          ),
                        ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                    key: const PageStorageKey('shopping_by_recipe'),
                    children: [
                      for (final group in groups)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Material(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: const BorderSide(color: borderSubtle),
                            ),
                            child: ExpansionTile(
                              key: PageStorageKey(group.id),
                              initiallyExpanded: true,
                              maintainState: true,
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                6,
                                0,
                                6,
                                10,
                              ),
                              shape: const Border(),
                              collapsedShape: const Border(),
                              leading: Icon(
                                group.id == 'manual'
                                    ? Icons.shopping_basket_outlined
                                    : Icons.restaurant_menu_rounded,
                                color: mossDeep,
                              ),
                              title: Text(
                                group.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              subtitle: Text(
                                [
                                  if (shoppingBatches(group.items).isNotEmpty)
                                    '${shoppingBatches(group.items).length}回追加',
                                  if (group.recipeId != null &&
                                      group.items.any((i) => i.batchId == null))
                                    '以前の項目・個別追加を含む',
                                  '${shoppingTotalRows(group.items).where((row) => row.checked).length} / ${shoppingTotalRows(group.items).length} 件購入済み',
                                ].join('・'),
                              ),
                              children: [
                                if (shoppingBatches(group.items).isNotEmpty &&
                                    group.id.startsWith('recipe:'))
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      4,
                                      12,
                                      12,
                                    ),
                                    child: Wrap(
                                      spacing: 12,
                                      runSpacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        const Text('追加した料理の合計'),
                                        RecipeServingStepper(
                                          servings: shoppingServings(
                                            group.items,
                                          ),
                                          unit:
                                              recipes
                                                  .where(
                                                    (r) =>
                                                        r.id == group.recipeId!,
                                                  )
                                                  .firstOrNull
                                                  ?.servingUnit ??
                                              '人分',
                                          onChanged: (value) => _perform(
                                            () => controller
                                                .setShoppingRecipeServings(
                                                  group.recipeId!,
                                                  value,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                for (final row in shoppingTotalRows(
                                  group.items,
                                ))
                                  _ShoppingTile(
                                    key: ValueKey(row.name),
                                    name: row.name,
                                    quantity: row.quantity,
                                    checked: row.checked,
                                    partial: row.partiallyChecked,
                                    flat: true,
                                    onChanged: () => _perform(
                                      () => controller.setShoppingItemsChecked(
                                        row.items.map((i) => i.id),
                                        !row.checked,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _sourceLabels(List<ShoppingItem> items, List<Recipe> recipes) {
    final names = {for (final recipe in recipes) recipe.id: recipe.title};
    final labels = <String>{};
    for (final item in items) {
      if (item.recipeIds.isEmpty) labels.add('その他');
      for (final id in item.recipeIds) {
        final source = items.where(
          (i) => i.recipeIds.length == 1 && i.recipeIds.single == id,
        );
        final count = shoppingBatches(source).length;
        labels.add(
          '${names[id] ?? '元の料理が削除された項目'}${count > 0 ? '（$count回追加）' : ''}',
        );
      }
    }
    final purchased = items.where((item) => item.checked).length;
    return '${labels.join('・')}${items.length > 1 ? ' / $purchased/${items.length}件購入済み' : ''}';
  }

  Future<void> _add() async {
    final controller = RecipeScope.read(context);
    final item = await showAddShoppingItemDialog(
      context,
      recipes: controller.savedRecipes,
    );
    if (!mounted || item == null) return;
    await _perform(
      () => controller.addShoppingItem(
        item.name,
        item.quantity,
        recipeId: item.recipeIds.firstOrNull,
      ),
    );
  }
}

class _ShoppingTile extends StatelessWidget {
  const _ShoppingTile({
    super.key,
    required this.name,
    required this.quantity,
    required this.checked,
    required this.onChanged,
    this.partial = false,
    this.caption,
    this.flat = false,
  });
  final String name, quantity;
  final bool checked, partial, flat;
  final String? caption;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: flat ? 0 : 8),
    child: Material(
      color: flat
          ? Colors.transparent
          : checked
          ? mintSoft
          : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: CheckboxListTile(
        value: partial ? null : checked,
        tristate: true,
        onChanged: (_) => onChanged(),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.fromLTRB(2, 4, 12, 4),
        title: Text(
          name,
          style: TextStyle(
            decoration: checked ? TextDecoration.lineThrough : null,
            color: checked ? secondaryInk : ink,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (quantity.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(quantity, style: const TextStyle(color: mossDeep)),
              ),
            if (caption?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  caption!,
                  style: const TextStyle(fontSize: 12, color: secondaryInk),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<ShoppingItem?> showAddShoppingItemDialog(
  BuildContext context, {
  List<Recipe> recipes = const [],
}) => showDialog<ShoppingItem>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _AddShoppingItemDialog(recipes: recipes),
);

class _AddShoppingItemDialog extends StatefulWidget {
  const _AddShoppingItemDialog({required this.recipes});
  final List<Recipe> recipes;
  @override
  State<_AddShoppingItemDialog> createState() => _AddShoppingItemDialogState();
}

class _AddShoppingItemDialogState extends State<_AddShoppingItemDialog> {
  final _name = TextEditingController();
  final _quantity = TextEditingController();
  final _form = GlobalKey<FormState>();
  String _recipeId = '';
  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
    contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
    actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
    title: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: mintSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.shopping_basket_outlined, color: mossDeep),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text('買うものを追加', style: Theme.of(context).textTheme.titleLarge),
        ),
      ],
    ),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '買っておきたいものを、忘れないうちに。',
              style: TextStyle(color: secondaryInk),
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const ValueKey('shopping_name'),
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '品名',
                hintText: '例：にんじん、牛乳',
              ),
              validator: (value) =>
                  value?.trim().isNotEmpty == true ? null : '品名を入力してください',
            ),
            const SizedBox(height: 18),
            TextFormField(
              key: const ValueKey('shopping_quantity'),
              controller: _quantity,
              decoration: const InputDecoration(
                labelText: '数量（任意）',
                hintText: '例：2本、500ml、1袋',
              ),
            ),
            if (widget.recipes.isNotEmpty) ...[
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'まとめる料理（任意）'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('その他の買うもの')),
                  for (final recipe in widget.recipes)
                    DropdownMenuItem(
                      value: recipe.id,
                      child: Text(recipe.title, maxLines: 2),
                    ),
                ],
                onChanged: (value) => setState(() => _recipeId = value ?? ''),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: () {
                if (_form.currentState?.validate() != true) return;
                Navigator.pop(
                  context,
                  ShoppingItem(
                    name: _name.text.trim(),
                    quantity: _quantity.text.trim(),
                    recipeIds: _recipeId.isEmpty ? [] : [_recipeId],
                  ),
                );
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('追加'),
            ),
          ),
        ],
      ),
    ],
  );
}
