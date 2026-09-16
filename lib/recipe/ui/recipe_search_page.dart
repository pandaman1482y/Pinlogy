import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../models/recipe_models.dart';
import '../recipe_controller.dart';
import '../recipe_scope.dart';
import 'recipe_detail_page.dart';
import 'recipe_widgets.dart';

class RecipeSearchPage extends StatefulWidget {
  const RecipeSearchPage({super.key});

  @override
  State<RecipeSearchPage> createState() => _RecipeSearchPageState();
}

class _RecipeSearchPageState extends State<RecipeSearchPage> {
  final _query = TextEditingController();
  RecipeFilters _filters = const RecipeFilters();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = RecipeScope.of(context);
    final recipes = controller.filteredRecipes(query: _query.text, filters: _filters);
    return Scaffold(
      appBar: AppBar(title: const Text('検索')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '料理名、材料、工程、投稿者から検索',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '消去',
                          onPressed: () => setState(_query.clear),
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showFilters(context, controller),
                      icon: Badge(
                        isLabelVisible: !_filters.isEmpty,
                        child: const Icon(Icons.tune_rounded),
                      ),
                      label: const Text('絞り込み'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showSort(context, controller),
                      icon: const Icon(Icons.swap_vert_rounded),
                      label: Text(controller.snapshot.sort.label, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Text('${recipes.length}件', style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          if (recipes.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.search_off_rounded, size: 46, color: secondaryInk),
                      const SizedBox(height: 12),
                      Text('一致するレシピがありません', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 6),
                      const Text('言葉を短くするか、絞り込みを解除してください。'),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 4 / 5,
                ),
                itemCount: recipes.length,
                itemBuilder: (_, index) {
                  final recipe = recipes[index];
                  return RecipeGridCard(
                    recipe: recipe,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => RecipeDetailPage(recipeId: recipe.id)),
                    ),
                    onFavorite: () => controller.toggleFavorite(recipe),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showSort(BuildContext context, RecipeController controller) async {
    final selected = await showModalBottomSheet<RecipeSort>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final sort in RecipeSort.values)
              RadioListTile<RecipeSort>(
                value: sort,
                groupValue: controller.snapshot.sort,
                title: Text(sort.label),
                onChanged: (value) => Navigator.pop(sheetContext, value),
              ),
          ],
        ),
      ),
    );
    if (selected != null) await controller.setSort(selected);
  }

  Future<void> _showFilters(BuildContext context, RecipeController controller) async {
    final recipes = controller.savedRecipes;
    String? category = _filters.category;
    String? cuisine = _filters.cuisine;
    String? mainIngredient = _filters.mainIngredient;
    String? method = _filters.method;
    String? difficulty = _filters.difficulty;
    String? sourceService = _filters.sourceService;
    int? maxMinutes = _filters.maxMinutes;
    var favorite = _filters.favoritesOnly;
    var made = _filters.madeOnly;
    var review = _filters.needsReviewOnly;

    final result = await showModalBottomSheet<RecipeFilters>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('絞り込み', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 16),
                  _DropdownFilter(
                    label: 'カテゴリ',
                    value: category,
                    values: _distinct(recipes.map((recipe) => recipe.category)),
                    onChanged: (value) => setSheetState(() => category = value),
                  ),
                  const SizedBox(height: 10),
                  _DropdownFilter(
                    label: '料理ジャンル',
                    value: cuisine,
                    values: _distinct(recipes.map((recipe) => recipe.cuisine)),
                    onChanged: (value) => setSheetState(() => cuisine = value),
                  ),
                  const SizedBox(height: 10),
                  _DropdownFilter(
                    label: '主な食材',
                    value: mainIngredient,
                    values: _distinct(
                      recipes.map((recipe) => recipe.mainIngredient),
                    ),
                    onChanged: (value) =>
                        setSheetState(() => mainIngredient = value),
                  ),
                  const SizedBox(height: 10),
                  _DropdownFilter(
                    label: '調理法',
                    value: method,
                    values: _distinct(recipes.map((recipe) => recipe.method)),
                    onChanged: (value) => setSheetState(() => method = value),
                  ),
                  const SizedBox(height: 10),
                  _DropdownFilter(
                    label: '難易度',
                    value: difficulty,
                    values: _distinct(
                      recipes.map((recipe) => recipe.difficulty),
                    ),
                    onChanged: (value) =>
                        setSheetState(() => difficulty = value),
                  ),
                  const SizedBox(height: 10),
                  _DropdownFilter(
                    label: '取り込み元',
                    value: sourceService,
                    values: _distinct(
                      recipes.map((recipe) => recipe.sourceService),
                    ),
                    onChanged: (value) =>
                        setSheetState(() => sourceService = value),
                  ),
                  const SizedBox(height: 14),
                  Text('調理時間', style: Theme.of(context).textTheme.titleMedium),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final value in const [15, 30, 60])
                        ChoiceChip(
                          label: Text('$value分以内'),
                          selected: maxMinutes == value,
                          onSelected: (selected) => setSheetState(() => maxMinutes = selected ? value : null),
                        ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('お気に入りのみ'),
                    value: favorite,
                    onChanged: (value) => setSheetState(() => favorite = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('作ったことがある'),
                    value: made,
                    onChanged: (value) => setSheetState(() => made = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('要確認のみ'),
                    value: review,
                    onChanged: (value) => setSheetState(() => review = value),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext, const RecipeFilters()),
                          child: const Text('リセット'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(
                            sheetContext,
                            RecipeFilters(
                              category: category,
                              cuisine: cuisine,
                              mainIngredient: mainIngredient,
                              method: method,
                              maxMinutes: maxMinutes,
                              difficulty: difficulty,
                              sourceService: sourceService,
                              favoritesOnly: favorite,
                              madeOnly: made,
                              needsReviewOnly: review,
                            ),
                          ),
                          child: const Text('適用'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (result != null) setState(() => _filters = result);
  }
}

class _DropdownFilter extends StatelessWidget {
  const _DropdownFilter({required this.label, required this.value, required this.values, required this.onChanged});
  final String label;
  final String? value;
  final List<String> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String?>(
    value: value,
    decoration: InputDecoration(labelText: label),
    items: [
      const DropdownMenuItem<String?>(value: null, child: Text('すべて')),
      ...values.map((item) => DropdownMenuItem<String?>(value: item, child: Text(item))),
    ],
    onChanged: onChanged,
  );
}

List<String> _distinct(Iterable<String?> values) => values
    .whereType<String>()
    .where((value) => value.trim().isNotEmpty)
    .toSet()
    .toList()
  ..sort();
