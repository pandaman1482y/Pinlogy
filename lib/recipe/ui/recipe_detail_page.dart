import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../models/recipe_models.dart';
import '../recipe_scope.dart';
import 'cooking_mode_page.dart';
import 'recipe_editor_page.dart';
import 'recipe_widgets.dart';

class RecipeDetailPage extends StatefulWidget {
  const RecipeDetailPage({super.key, required this.recipeId});

  final String recipeId;

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  final _materialsKey = GlobalKey();
  final _stepsKey = GlobalKey();
  double? _servings;

  @override
  Widget build(BuildContext context) {
    final controller = RecipeScope.of(context);
    final recipe = controller.recipeById(widget.recipeId);
    if (recipe == null) {
      return const Scaffold(body: Center(child: Text('このレシピは削除されました')));
    }
    final servings = _servings ?? recipe.servings;
    final multiplier = recipe.servings <= 0 ? 1.0 : servings / recipe.servings;
    final related = controller.relatedRecipes(recipe);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 330,
            backgroundColor: Colors.white,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  RecipeImage(path: recipe.coverImagePath),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x42000000), Colors.transparent, Color(0x66000000)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                tooltip: recipe.isFavorite ? 'お気に入りから外す' : 'お気に入り',
                style: IconButton.styleFrom(backgroundColor: Colors.black38),
                onPressed: () => controller.toggleFavorite(recipe),
                icon: Icon(
                  recipe.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                ),
              ),
              IconButton(
                tooltip: '編集',
                style: IconButton.styleFrom(backgroundColor: Colors.black38),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RecipeEditorPage(recipeId: recipe.id),
                  ),
                ),
                icon: const Icon(Icons.edit_rounded),
              ),
              PopupMenuButton<String>(
                tooltip: 'その他',
                color: Colors.white,
                iconColor: Colors.white,
                onSelected: (value) {
                  if (value == 'delete') _deleteRecipe(context, recipe);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, color: errorColor),
                        SizedBox(width: 10),
                        Text('レシピを削除'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(recipe.title, style: Theme.of(context).textTheme.headlineLarge),
                  if (recipe.description?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      recipe.description!,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: secondaryInk),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(Icons.schedule_rounded, compactDuration(recipe.totalMinutes)),
                      if (recipe.category != null)
                        _InfoChip(Icons.restaurant_rounded, recipe.category!),
                      if (recipe.difficulty != null)
                        _InfoChip(Icons.signal_cellular_alt_rounded, recipe.difficulty!),
                      if (recipe.sourceService != null)
                        _InfoChip(Icons.play_circle_outline_rounded, recipe.sourceService!),
                    ],
                  ),
                  if (recipe.status == RecipeStatus.needsReview ||
                      recipe.warnings.isNotEmpty ||
                      recipe.needsReviewFields.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _ReviewWarning(recipe: recipe),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _jumpTo(_materialsKey),
                          icon: const Icon(Icons.shopping_basket_outlined),
                          label: const Text('材料へ'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _jumpTo(_stepsKey),
                          icon: const Icon(Icons.format_list_numbered_rounded),
                          label: const Text('作り方へ'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Row(
                    key: _materialsKey,
                    children: [
                      Expanded(
                        child: Text('材料', style: Theme.of(context).textTheme.headlineMedium),
                      ),
                      _ServingStepper(
                        servings: servings,
                        onChanged: (value) => setState(() => _servings = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final part in recipe.parts) ...[
                    if (recipe.parts.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 6),
                        child: Text(part.name, style: Theme.of(context).textTheme.titleLarge),
                      ),
                    for (final ingredient in part.ingredients)
                      _IngredientRow(
                        ingredient: ingredient,
                        quantity: ingredient.quantityFor(multiplier),
                        onEvidence: () => _showEvidence(context, recipe, ingredient.evidenceId),
                      ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await controller.addToShoppingList(recipe, multiplier);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('買い物リストに追加しました')),
                        );
                      },
                      icon: const Icon(Icons.add_shopping_cart_rounded),
                      label: const Text('材料を買い物リストへ'),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text('作り方', key: _stepsKey, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  for (final part in recipe.parts) ...[
                    if (recipe.parts.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 8),
                        child: Text(part.name, style: Theme.of(context).textTheme.titleLarge),
                      ),
                    for (var index = 0; index < part.steps.length; index++)
                      _StepRow(
                        number: index + 1,
                        step: part.steps[index],
                        onEvidence: () => _showEvidence(
                          context,
                          recipe,
                          part.steps[index].evidenceId,
                        ),
                      ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: recipe.allSteps.isEmpty
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => CookingModePage(recipeId: recipe.id),
                                ),
                              ),
                      icon: const Icon(Icons.soup_kitchen_rounded),
                      label: const Text('料理モードを始める'),
                    ),
                  ),
                  if (recipe.nutrition != null) ...[
                    const SizedBox(height: 30),
                    _NutritionPanel(nutrition: recipe.nutrition!),
                  ],
                  if (recipe.evidence.isNotEmpty) ...[
                    const SizedBox(height: 30),
                    Text('解析の根拠', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 6),
                    Text(
                      '画像・字幕・投稿文のどこから読み取ったか確認できます。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 126,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: recipe.evidence.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, index) {
                          final item = recipe.evidence[index];
                          return _EvidenceCard(
                            evidence: item,
                            onTap: () => _showEvidence(context, recipe, item.id),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 30),
                  SoftPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('記録と元投稿', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _recordMade(context, recipe),
                                icon: const Icon(Icons.check_circle_outline_rounded),
                                label: Text(recipe.madeCount == 0 ? '作った' : '作った ${recipe.madeCount}回'),
                              ),
                            ),
                            if (recipe.sourceUrl != null) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _openSource(recipe.sourceUrl!),
                                  icon: const Icon(Icons.open_in_new_rounded),
                                  label: const Text('元投稿'),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: () => _showCollections(context, recipe),
                            icon: const Icon(Icons.folder_outlined),
                            label: const Text('コレクションに整理'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (related.isNotEmpty) ...[
                    const SizedBox(height: 30),
                    Text('関連するレシピ', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 184,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: related.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, index) {
                          final item = related[index];
                          return SizedBox(
                            width: 142,
                            child: RecipeGridCard(
                              recipe: item,
                              onTap: () => Navigator.of(context).pushReplacement(
                                MaterialPageRoute<void>(
                                  builder: (_) => RecipeDetailPage(recipeId: item.id),
                                ),
                              ),
                              onFavorite: () => controller.toggleFavorite(item),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Center(
                    child: TextButton(
                      onPressed: () => _reportProblem(context, recipe),
                      child: const Text('解析内容に間違いがありますか？  報告'),
                    ),
                  ),
                  Center(
                    child: Text(
                      'AI解析には誤りや材料の見落としが含まれる場合があります。\nアレルギーがある場合は元投稿と商品表示を必ず確認してください。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: secondaryInk),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _jumpTo(GlobalKey key) {
    final target = key.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 350));
    }
  }

  Future<void> _openSource(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showEvidence(BuildContext context, Recipe recipe, String? id) async {
    if (id == null) return;
    final evidence = recipe.evidence.where((item) => item.id == id).firstOrNull;
    if (evidence == null) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(evidence.label, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (evidence.imagePath != null)
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: RecipeImage(
                    path: evidence.imagePath,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              if (evidence.timestampSeconds != null) ...[
                const SizedBox(height: 10),
                Text('動画 ${timestampLabel(evidence.timestampSeconds!)} 付近'),
              ],
              if (evidence.excerpt != null) ...[
                const SizedBox(height: 8),
                Text(evidence.excerpt!),
              ],
              if (evidence.confidencePercent != null) ...[
                const SizedBox(height: 8),
                Text('読取確度 ${evidence.confidencePercent}%'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _recordMade(BuildContext context, Recipe recipe) async {
    final note = TextEditingController();
    var rating = 4;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('作った記録'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = 1; index <= 5; index++)
                    IconButton(
                      onPressed: () => setDialogState(() => rating = index),
                      icon: Icon(
                        index <= rating ? Icons.star_rounded : Icons.star_border_rounded,
                        color: warningColor,
                      ),
                    ),
                ],
              ),
              TextField(
                controller: note,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'メモ（任意）'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('記録する')),
          ],
        ),
      ),
    );
    if (accepted == true && context.mounted) {
      await RecipeScope.read(context).recordCooked(
        recipe,
        rating: rating,
        note: note.text.trim().isEmpty ? null : note.text.trim(),
      );
    }
    note.dispose();
  }

  Future<void> _deleteRecipe(BuildContext context, Recipe recipe) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('レシピを削除しますか？'),
        content: Text('「${recipe.title}」をレシピ一覧から削除します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: errorColor),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;
    final controller = RecipeScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await controller.deleteRecipe(recipe);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('レシピを削除しました'),
        action: SnackBarAction(
          label: '元に戻す',
          onPressed: () => controller.saveRecipe(recipe),
        ),
      ),
    );
  }

  Future<void> _reportProblem(BuildContext context, Recipe recipe) async {
    const types = ['材料', '分量', '工程', '料理が混ざっている', '分け方', 'その他'];
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('どこに間違いがありますか？', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final type in types)
                ListTile(
                  title: Text(type),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await RecipeScope.read(context).submitFeedback(recipe, type);
                    if (!sheetContext.mounted) return;
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('報告を保存しました。ありがとうございます')),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCollections(BuildContext context, Recipe recipe) async {
    final controller = RecipeScope.read(context);
    if (controller.snapshot.collections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('マイページでコレクションを作成できます')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('コレクション', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final collection in controller.snapshot.collections)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: collection.recipeIds.contains(recipe.id),
                  title: Text(collection.name),
                  onChanged: (_) => controller.toggleRecipeInCollection(recipe, collection),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(color: mintSoft, borderRadius: BorderRadius.circular(8)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: mossDeep),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelLarge),
      ],
    ),
  );
}

class _ServingStepper extends StatelessWidget {
  const _ServingStepper({required this.servings, required this.onChanged});
  final double servings;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: mintSoft, borderRadius: BorderRadius.circular(12)),
    child: Row(
      children: [
        IconButton(
          tooltip: '人数を減らす',
          visualDensity: VisualDensity.compact,
          onPressed: servings <= 0.5 ? null : () => onChanged(servings - 0.5),
          icon: const Icon(Icons.remove_rounded, size: 18),
        ),
        Text('${servings.toStringAsFixed(servings % 1 == 0 ? 0 : 1)}人分'),
        IconButton(
          tooltip: '人数を増やす',
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(servings + 0.5),
          icon: const Icon(Icons.add_rounded, size: 18),
        ),
      ],
    ),
  );
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.ingredient, required this.quantity, required this.onEvidence});
  final RecipeIngredient ingredient;
  final String quantity;
  final VoidCallback onEvidence;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Expanded(child: Text(ingredient.name)),
        if (ingredient.evidenceId != null)
          IconButton(
            tooltip: '根拠を見る',
            onPressed: onEvidence,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.image_outlined, size: 18, color: secondaryInk),
          ),
        Text(quantity, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.number, required this.step, required this.onEvidence});
  final int number;
  final RecipeStep step;
  final VoidCallback onEvidence;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: mossDeep,
          foregroundColor: Colors.white,
          child: Text('$number', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step.instruction, style: Theme.of(context).textTheme.bodyLarge),
              if (step.durationSeconds != null) ...[
                const SizedBox(height: 5),
                Text(
                  '目安 ${_durationLabel(step.durationSeconds!)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: mossDeep),
                ),
              ],
            ],
          ),
        ),
        if (step.evidenceId != null)
          IconButton(
            tooltip: '根拠を見る',
            visualDensity: VisualDensity.compact,
            onPressed: onEvidence,
            icon: const Icon(Icons.image_outlined, size: 19, color: secondaryInk),
          ),
      ],
    ),
  );
}

class _ReviewWarning extends StatelessWidget {
  const _ReviewWarning({required this.recipe});
  final Recipe recipe;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E8),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: warningColor.withValues(alpha: 0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.warning_amber_rounded, color: warningColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            [
              'AIが読み取れなかった箇所があります。元投稿と照合してください。',
              ...recipe.warnings,
              if (recipe.needsReviewFields.isNotEmpty)
                '要確認: ${recipe.needsReviewFields.join('、')}',
            ].join('\n'),
          ),
        ),
      ],
    ),
  );
}

class _NutritionPanel extends StatelessWidget {
  const _NutritionPanel({required this.nutrition});
  final RecipeNutrition nutrition;

  @override
  Widget build(BuildContext context) => SoftPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('栄養の目安', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Text([
          if (nutrition.calories != null) '${nutrition.calories} kcal',
          if (nutrition.proteinGrams != null) 'P ${nutrition.proteinGrams}g',
          if (nutrition.fatGrams != null) 'F ${nutrition.fatGrams}g',
          if (nutrition.carbohydrateGrams != null) 'C ${nutrition.carbohydrateGrams}g',
        ].join('  ·  ')),
        const SizedBox(height: 6),
        Text('AIによる概算です。実際の商品・分量で変わります。', style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.evidence, required this.onTap});
  final RecipeEvidence evidence;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 110,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            RecipeImage(path: evidence.imagePath),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xB3000000)],
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 7,
              child: Text(
                evidence.timestampSeconds == null
                    ? evidence.label
                    : '${timestampLabel(evidence.timestampSeconds!)}  ${evidence.label}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _durationLabel(int seconds) {
  if (seconds < 60) return '$seconds秒';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return rest == 0 ? '$minutes分' : '$minutes分$rest秒';
}
