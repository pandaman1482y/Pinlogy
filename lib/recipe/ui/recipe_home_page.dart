import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../models/recipe_models.dart';
import '../recipe_scope.dart';
import 'recipe_detail_page.dart';
import 'recipe_editor_page.dart';
import 'recipe_selection_page.dart';
import 'recipe_widgets.dart';

class RecipeHomePage extends StatefulWidget {
  const RecipeHomePage({super.key});

  @override
  State<RecipeHomePage> createState() => _RecipeHomePageState();
}

class _RecipeHomePageState extends State<RecipeHomePage> {
  String _collection = 'すべて';

  @override
  Widget build(BuildContext context) {
    final controller = RecipeScope.of(context);
    var recipes = controller.filteredRecipes();
    if (_collection == 'お気に入り') {
      recipes = recipes.where((recipe) => recipe.isFavorite).toList();
    } else if (_collection == '最近作った') {
      recipes = recipes.where((recipe) => recipe.madeCount > 0).toList();
    } else if (_collection != 'すべて') {
      final selectedCollection = controller.snapshot.collections
          .where((item) => item.id == _collection)
          .firstOrNull;
      if (selectedCollection != null) {
        recipes = recipes
            .where((recipe) => selectedCollection.recipeIds.contains(recipe.id))
            .toList();
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('レシピ'),
        actions: [
          IconButton(
            tooltip: '並び順',
            onPressed: () => _selectSort(context),
            icon: const Icon(Icons.swap_vert_rounded),
          ),
          IconButton(
            tooltip: 'レシピを追加',
            onPressed: () => _showAddMenu(context),
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.syncFromIntake,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (controller.activeImports.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    children: controller.activeImports
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ImportCard(item: item),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 47,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final label in const ['すべて', 'お気に入り', '最近作った'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _collection == label,
                          onSelected: (_) =>
                              setState(() => _collection = label),
                        ),
                      ),
                    for (final collection in controller.snapshot.collections)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(collection.name),
                          selected: _collection == collection.id,
                          onSelected: (_) =>
                              setState(() => _collection = collection.id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (recipes.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyRecipes(onAdd: () => _showAddMenu(context)),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 4 / 5,
                  ),
                  itemCount: recipes.length,
                  itemBuilder: (context, index) {
                    final recipe = recipes[index];
                    return RecipeGridCard(
                      recipe: recipe,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RecipeDetailPage(recipeId: recipe.id),
                        ),
                      ),
                      onFavorite: () => controller.toggleFavorite(recipe),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectSort(BuildContext context) async {
    final controller = RecipeScope.read(context);
    final selected = await showModalBottomSheet<RecipeSort>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '一覧の並び順',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
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

  Future<void> _showAddMenu(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('レシピを追加', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: mint,
                  child: Icon(Icons.ios_share_rounded, color: mossDeep),
                ),
                title: const Text('SNSから取り込む'),
                subtitle: const Text('InstagramやTikTokの共有からこのアプリを選択'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('SNSの共有メニューからこのアプリを選んでください')),
                  );
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: mint,
                  child: Icon(Icons.link_rounded, color: mossDeep),
                ),
                title: const Text('投稿URLを貼り付ける'),
                subtitle: const Text('Instagram・TikTokのURLから取り込む'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _importUrl(context);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: mint,
                  child: Icon(Icons.edit_note_rounded, color: mossDeep),
                ),
                title: const Text('手動で作成'),
                subtitle: const Text('材料と工程を自分で入力'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RecipeEditorPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _importUrl(BuildContext context) async {
    final input = TextEditingController();
    final rawUrl = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('投稿URLから取り込む'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Instagram・TikTokのURL',
            hintText: 'https://www.instagram.com/…',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, input.text),
            child: const Text('取り込む'),
          ),
        ],
      ),
    );
    input.dispose();
    if (!context.mounted || rawUrl == null || rawUrl.trim().isEmpty) return;
    final controller = RecipeScope.read(context);
    final existing = controller.existingRecipeForUrl(rawUrl);
    if (existing != null) {
      final openExisting = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('この投稿は保存済みです'),
          content: Text('「${existing.title}」を開きますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('閉じる'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('レシピを見る'),
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      if (openExisting == true) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RecipeDetailPage(recipeId: existing.id),
          ),
        );
      }
      return;
    } else {
      final active = controller.existingImportForUrl(rawUrl);
      if (active != null &&
          active.status != RecipeImportStatus.completed &&
          active.status != RecipeImportStatus.cancelled) {
        final failed =
            active.status == RecipeImportStatus.failed ||
            active.status == RecipeImportStatus.retryWaiting;
        final retry = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              failed
                  ? 'この投稿は前回解析できませんでした'
                  : active.status == RecipeImportStatus.queued
                  ? 'この投稿は解析待ちです'
                  : 'この投稿は現在解析中です',
            ),
            content: Text(
              failed ? '再試行する場合だけ解析を開始します。' : '新しい解析や利用回数の追加予約は行いません。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('閉じる'),
              ),
              if (failed)
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('再試行'),
                )
              else
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('進捗を見る'),
                ),
            ],
          ),
        );
        if (retry == true) await controller.retryImport(active);
        return;
      }
    }
    try {
      await controller.importFromUrl(rawUrl);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('受付しました。アプリを閉じても解析を続けます')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class _ImportCard extends StatelessWidget {
  const _ImportCard({required this.item});

  final RecipeImport item;

  @override
  Widget build(BuildContext context) {
    final controller = RecipeScope.of(context);
    final selecting = item.status == RecipeImportStatus.awaitingSelection;
    final failed =
        item.status == RecipeImportStatus.failed ||
        item.status == RecipeImportStatus.retryWaiting;
    return SoftPanel(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: RecipeImage(
              path: item.coverImagePath,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (!selecting && !failed) ...[
                      const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Expanded(
                      child: Text(
                        item.status.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  item.message ??
                      (failed ? '元URLを使って再試行できます' : 'アプリを閉じてもサーバーで処理を続けます'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (selecting || failed) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      if (selecting) {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                RecipeSelectionPage(importId: item.id),
                          ),
                        );
                      } else {
                        controller.retryImport(item);
                      }
                    },
                    icon: Icon(
                      selecting
                          ? Icons.checklist_rounded
                          : Icons.refresh_rounded,
                    ),
                    label: Text(selecting ? '保存する料理を選ぶ' : '再試行'),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: '一覧から閉じる',
            onPressed: () => controller.cancelImport(item),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _EmptyRecipes extends StatelessWidget {
  const _EmptyRecipes({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_stories_outlined, size: 54, color: moss),
          const SizedBox(height: 16),
          Text('気になるレシピを集めよう', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'SNS投稿を共有すると、材料・分量・工程を整理して保存します。',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: secondaryInk),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('最初のレシピを追加'),
          ),
        ],
      ),
    ),
  );
}
