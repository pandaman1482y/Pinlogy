import 'package:flutter/material.dart';

import '../../core/ids.dart';
import '../../core/theme.dart';
import '../models/recipe_models.dart';
import '../recipe_scope.dart';

class RecipeEditorPage extends StatefulWidget {
  const RecipeEditorPage({super.key, this.recipeId});

  final String? recipeId;

  @override
  State<RecipeEditorPage> createState() => _RecipeEditorPageState();
}

class _RecipeEditorPageState extends State<RecipeEditorPage> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _sourceUrl = TextEditingController();
  final _servings = TextEditingController(text: '2');
  final _minutes = TextEditingController();
  final _category = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  List<RecipePart> _parts = [RecipePart(name: '本体')];
  Recipe? _original;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final id = widget.recipeId;
    if (id == null) return;
    _original = RecipeScope.read(context).recipeById(id);
    final recipe = _original;
    if (recipe == null) return;
    _title.text = recipe.title;
    _description.text = recipe.description ?? '';
    _sourceUrl.text = recipe.sourceUrl ?? '';
    _servings.text = recipe.servings.toStringAsFixed(
      recipe.servings % 1 == 0 ? 0 : 1,
    );
    _minutes.text = recipe.totalMinutes?.toString() ?? '';
    _category.text = recipe.category ?? '';
    _parts = recipe.parts
        .map(
          (part) => RecipePart(
            id: part.id,
            name: part.name,
            ingredients: List.of(part.ingredients),
            steps: List.of(part.steps),
          ),
        )
        .toList();
    if (_parts.isEmpty) _parts = [RecipePart(name: '本体')];
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _sourceUrl.dispose();
    _servings.dispose();
    _minutes.dispose();
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_original == null ? 'レシピを作成' : 'レシピを編集'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
          const SizedBox(width: 6),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: '料理名 *'),
              validator: (value) =>
                  value?.trim().isEmpty == true ? '料理名を入力してください' : null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '説明・メモ'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _servings,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: '基準人数'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '調理時間（分）'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _category,
              decoration: const InputDecoration(labelText: 'カテゴリ'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sourceUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: '元投稿URL（任意）'),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '材料と作り方',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: _addPart,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('パート'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var partIndex = 0; partIndex < _parts.length; partIndex++)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _PartEditor(
                  part: _parts[partIndex],
                  canDelete: _parts.length > 1,
                  onRename: () => _renamePart(partIndex),
                  onDelete: () => setState(() => _parts.removeAt(partIndex)),
                  onAddIngredient: () => _addIngredient(partIndex),
                  onDeleteIngredient: (index) =>
                      _deleteIngredient(partIndex, index),
                  onAddStep: () => _addStep(partIndex),
                  onDeleteStep: (index) => _deleteStep(partIndex, index),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPart() async {
    final name = await _askText('パートを追加', '例：タレ、出汁、トッピング');
    if (name == null || name.trim().isEmpty) return;
    setState(() => _parts.add(RecipePart(name: name.trim())));
  }

  Future<void> _renamePart(int index) async {
    final name = await _askText('パート名', '例：本体、タレ', initial: _parts[index].name);
    if (name == null || name.trim().isEmpty) return;
    final current = _parts[index];
    setState(() {
      _parts[index] = RecipePart(
        id: current.id,
        name: name.trim(),
        ingredients: current.ingredients,
        steps: current.steps,
      );
    });
  }

  Future<void> _addIngredient(int partIndex) async {
    final name = TextEditingController();
    final quantity = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('材料を追加'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '材料名'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: quantity,
              decoration: const InputDecoration(labelText: '分量（例：小さじ1）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('追加'),
          ),
        ],
      ),
    );
    if (accepted == true && name.text.trim().isNotEmpty) {
      final current = _parts[partIndex];
      setState(() {
        _parts[partIndex] = RecipePart(
          id: current.id,
          name: current.name,
          ingredients: [
            ...current.ingredients,
            RecipeIngredient(
              name: name.text.trim(),
              originalText: quantity.text.trim(),
              scalable: false,
              userEdited: true,
            ),
          ],
          steps: current.steps,
        );
      });
    }
    name.dispose();
    quantity.dispose();
  }

  Future<void> _addStep(int partIndex) async {
    final text = await _askText('工程を追加', '作り方を入力');
    if (text == null || text.trim().isEmpty) return;
    final current = _parts[partIndex];
    setState(() {
      _parts[partIndex] = RecipePart(
        id: current.id,
        name: current.name,
        ingredients: current.ingredients,
        steps: [
          ...current.steps,
          RecipeStep(
            order: current.steps.length + 1,
            instruction: text.trim(),
            userEdited: true,
          ),
        ],
      );
    });
  }

  void _deleteIngredient(int partIndex, int ingredientIndex) {
    final current = _parts[partIndex];
    setState(() {
      _parts[partIndex] = RecipePart(
        id: current.id,
        name: current.name,
        ingredients: List.of(current.ingredients)..removeAt(ingredientIndex),
        steps: current.steps,
      );
    });
  }

  void _deleteStep(int partIndex, int stepIndex) {
    final current = _parts[partIndex];
    final steps = List<RecipeStep>.of(current.steps)..removeAt(stepIndex);
    setState(() {
      _parts[partIndex] = RecipePart(
        id: current.id,
        name: current.name,
        ingredients: current.ingredients,
        steps: steps
            .asMap()
            .entries
            .map(
              (entry) => RecipeStep(
                id: entry.value.id,
                order: entry.key + 1,
                instruction: entry.value.instruction,
                durationSeconds: entry.value.durationSeconds,
                evidenceId: entry.value.evidenceId,
                confidencePercent: entry.value.confidencePercent,
                userEdited: true,
              ),
            )
            .toList(),
      );
    });
  }

  Future<String?> _askText(String title, String hint, {String? initial}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: title.contains('工程') ? 4 : 1,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('決定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    final controller = RecipeScope.read(context);
    final original = _original;
    final sourcePostId = original?.sourcePostId ?? 'manual-${newId()}';
    final recipe = Recipe(
      id: original?.id,
      sourcePostId: sourcePostId,
      title: _title.text.trim(),
      description: _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      servings: double.tryParse(_servings.text) ?? 2,
      totalMinutes: int.tryParse(_minutes.text),
      category: _category.text.trim().isEmpty ? null : _category.text.trim(),
      parts: _parts,
      evidence: original?.evidence,
      coverImagePath: original?.coverImagePath,
      sourceUrl: _sourceUrl.text.trim().isEmpty ? null : _sourceUrl.text.trim(),
      sourceService:
          original?.sourceService ??
          (_sourceUrl.text.trim().isEmpty ? '手動' : 'URL'),
      status: RecipeStatus.ready,
      isFavorite: original?.isFavorite ?? false,
      isSaved: true,
      allergens: original?.allergens,
      warnings: original?.warnings,
      needsReviewFields: const [],
      userEditedFields: {
        ...?original?.userEditedFields,
        'title',
        'description',
        'servings',
        'totalMinutes',
        'category',
        'parts',
      },
      userNote: original?.userNote,
      nutrition: original?.nutrition,
      lastMadeAt: original?.lastMadeAt,
      madeCount: original?.madeCount ?? 0,
      createdAt: original?.createdAt,
    );
    await controller.addManualRecipe(recipe);
    if (mounted) Navigator.pop(context);
  }
}

class _PartEditor extends StatelessWidget {
  const _PartEditor({
    required this.part,
    required this.canDelete,
    required this.onRename,
    required this.onDelete,
    required this.onAddIngredient,
    required this.onDeleteIngredient,
    required this.onAddStep,
    required this.onDeleteStep,
  });

  final RecipePart part;
  final bool canDelete;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onAddIngredient;
  final ValueChanged<int> onDeleteIngredient;
  final VoidCallback onAddStep;
  final ValueChanged<int> onDeleteStep;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: mintSoft,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderSubtle),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                part.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: '名前を変更',
              onPressed: onRename,
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
            if (canDelete)
              IconButton(
                tooltip: 'パートを削除',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
          ],
        ),
        Text('材料', style: Theme.of(context).textTheme.titleMedium),
        if (part.ingredients.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('まだ材料がありません'),
          ),
        for (var index = 0; index < part.ingredients.length; index++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(part.ingredients[index].name),
            subtitle: Text(
              part.ingredients[index].originalText ??
                  part.ingredients[index].quantityFor(1),
            ),
            trailing: IconButton(
              onPressed: () => onDeleteIngredient(index),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        TextButton.icon(
          onPressed: onAddIngredient,
          icon: const Icon(Icons.add_rounded),
          label: const Text('材料を追加'),
        ),
        const Divider(height: 24),
        Text('作り方', style: Theme.of(context).textTheme.titleMedium),
        if (part.steps.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('まだ工程がありません'),
          ),
        for (var index = 0; index < part.steps.length; index++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 13,
              backgroundColor: mossDeep,
              foregroundColor: Colors.white,
              child: Text('${index + 1}', style: const TextStyle(fontSize: 11)),
            ),
            title: Text(part.steps[index].instruction),
            trailing: IconButton(
              onPressed: () => onDeleteStep(index),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        TextButton.icon(
          onPressed: onAddStep,
          icon: const Icon(Icons.add_rounded),
          label: const Text('工程を追加'),
        ),
      ],
    ),
  );
}
