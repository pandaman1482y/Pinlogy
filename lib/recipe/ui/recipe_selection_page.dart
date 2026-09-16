import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../models/recipe_models.dart';
import '../recipe_scope.dart';
import 'recipe_widgets.dart';

class RecipeSelectionPage extends StatefulWidget {
  const RecipeSelectionPage({super.key, required this.importId});

  final String importId;

  @override
  State<RecipeSelectionPage> createState() => _RecipeSelectionPageState();
}

class _RecipeSelectionPageState extends State<RecipeSelectionPage> {
  final Set<String> _selected = {};
  bool _seeded = false;

  @override
  Widget build(BuildContext context) {
    final controller = RecipeScope.of(context);
    final recipeImport = controller.snapshot.imports
        .where((item) => item.id == widget.importId)
        .firstOrNull;
    if (recipeImport == null) {
      return const Scaffold(body: Center(child: Text('取り込み情報が見つかりません')));
    }
    final recipes = controller.recipesForImport(recipeImport);
    if (!_seeded) {
      _seeded = true;
      _selected.addAll(recipes.map((recipe) => recipe.id));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('保存する料理を選択'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              if (_selected.length == recipes.length) {
                _selected.clear();
              } else {
                _selected.addAll(recipes.map((recipe) => recipe.id));
              }
            }),
            child: Text(_selected.length == recipes.length ? '選択解除' : 'すべて選択'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SoftPanel(
              child: Text(
                '1つの投稿から${recipes.length}件の料理を検出しました。タレや出汁は各料理の中でパート分けされています。',
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: recipes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, index) {
                final recipe = recipes[index];
                final selected = _selected.contains(recipe.id);
                return InkWell(
                  onTap: () => setState(() {
                    selected ? _selected.remove(recipe.id) : _selected.add(recipe.id);
                  }),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: selected ? mint : mintSoft,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: selected ? moss : borderSubtle),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 88,
                          height: 110,
                          child: RecipeImage(
                            path: recipe.coverImagePath,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(recipe.title, style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 6),
                              Text(
                                [
                                  compactDuration(recipe.totalMinutes),
                                  recipe.category,
                                  '${recipe.parts.length}パート',
                                ].whereType<String>().join(' · '),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (recipe.needsReviewFields.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                const Text('一部要確認', style: TextStyle(color: warningColor, fontWeight: FontWeight.w700)),
                              ],
                            ],
                          ),
                        ),
                        Checkbox(
                          value: selected,
                          onChanged: (_) => setState(() {
                            selected ? _selected.remove(recipe.id) : _selected.add(recipe.id);
                          }),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await controller.saveSelectedRecipes(recipeImport, _selected);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(_selected.isEmpty ? '保存せず完了' : '${_selected.length}件を保存'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
