import 'dart:convert';
import 'dart:async';

import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../../core/ids.dart';
import '../../core/theme.dart';
import '../models/recipe_models.dart';
import '../recipe_scope.dart';
import '../services/manual_recipe_photo_store.dart';
import 'recipe_widgets.dart';

class RecipeEditorPage extends StatefulWidget {
  const RecipeEditorPage({super.key, this.recipeId});
  final String? recipeId;
  @override
  State<RecipeEditorPage> createState() => _RecipeEditorPageState();
}

class _RecipeEditorPageState extends State<RecipeEditorPage>
    with WidgetsBindingObserver {
  final _titleKey = GlobalKey();
  final _descriptionKey = GlobalKey();
  final _titleFocus = FocusNode();
  final _descriptionFocus = FocusNode();
  Timer? _keyboardRevealTimer;
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _sourceUrl = TextEditingController();
  final _servings = TextEditingController(text: '2');
  final _servingUnit = TextEditingController(text: '人分');
  final _minutes = TextEditingController();
  final _category = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  List<RecipePart> _parts = [RecipePart(name: '本体')];
  Recipe? _original;
  bool _initialized = false;
  final _photos = ManualRecipePhotoStore();
  String? _photoPath;
  String? _draftPhotoPath;
  bool _choosingPhoto = false;
  bool _saving = false;
  bool _photoCommitted = false;

  Future<void> _deleteDraft(String? path) async {
    try {
      await _photos.deleteOwned(path);
    } catch (_) {
      /* best effort cleanup */
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _titleFocus.addListener(_revealFocusedInput);
    _descriptionFocus.addListener(_revealFocusedInput);
  }

  @override
  void didChangeMetrics() => _revealFocusedInput();

  void _revealFocusedInput() {
    _keyboardRevealTimer?.cancel();
    if (!_titleFocus.hasFocus && !_descriptionFocus.hasFocus) return;
    _keyboardRevealTimer = Timer(const Duration(milliseconds: 120), () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = _titleFocus.hasFocus
            ? _titleKey.currentContext
            : _descriptionFocus.hasFocus
            ? _descriptionKey.currentContext
            : null;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            alignment: 0.15,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }

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
    _photoPath = recipe.coverImagePath;
    _title.text = recipe.title;
    _description.text = recipe.description ?? '';
    _sourceUrl.text = recipe.sourceUrl ?? '';
    _servings.text = recipe.servings.toStringAsFixed(
      recipe.servings % 1 == 0 ? 0 : 1,
    );
    _servingUnit.text = recipe.servingUnit;
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
    WidgetsBinding.instance.removeObserver(this);
    _keyboardRevealTimer?.cancel();
    _titleFocus.removeListener(_revealFocusedInput);
    _descriptionFocus.removeListener(_revealFocusedInput);
    _titleFocus.dispose();
    _descriptionFocus.dispose();
    for (final field in [
      _title,
      _description,
      _sourceUrl,
      _servings,
      _servingUnit,
      _minutes,
      _category,
    ]) {
      field.dispose();
    }
    if (!_saving && !_photoCommitted) {
      unawaited(_deleteDraft(_draftPhotoPath));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: true,
    appBar: AppBar(
      title: Text(_original == null ? 'レシピを作成' : 'レシピを編集'),
      actions: [
        TextButton(
          onPressed: _saving || _choosingPhoto ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
        const SizedBox(width: 6),
      ],
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        children: [
          _buildPhotoSection(),
          const SizedBox(height: 18),
          _EditorSection(
            title: 'レシピの基本情報',
            icon: Icons.restaurant_menu_rounded,
            children: [
              TextFormField(
                key: _titleKey,
                controller: _title,
                focusNode: _titleFocus,
                scrollPadding: const EdgeInsets.only(bottom: 100, top: 24),
                decoration: const InputDecoration(
                  labelText: '料理名',
                  hintText: '例：鶏じゃが丼',
                ),
                validator: (value) =>
                    value?.trim().isEmpty != false ? '料理名を入力してください' : null,
              ),
              const SizedBox(height: 16),
              TextField(
                key: _descriptionKey,
                controller: _description,
                focusNode: _descriptionFocus,
                scrollPadding: const EdgeInsets.only(bottom: 100, top: 24),
                minLines: 3,
                maxLines: 6,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  labelText: '説明・メモ',
                  alignLabelWithHint: true,
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  hintText: '料理の紹介や、覚えておきたいことを書いてください',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _servings,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '基準数量',
                        hintText: '2',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _servingUnit,
                      decoration: const InputDecoration(
                        labelText: '単位',
                        hintText: '人分',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _minutes,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '調理時間',
                  hintText: '例：20',
                  suffixText: '分',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _category,
                decoration: const InputDecoration(
                  labelText: 'カテゴリ',
                  hintText: '例：丼もの',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _sourceUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: '元投稿URL（任意）'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  '材料と作り方',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton.icon(
                onPressed: _addPart,
                icon: const Icon(Icons.add_rounded),
                label: const Text('パート'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _parts.length; i++)
            Padding(
              key: ValueKey(_parts[i].id),
              padding: const EdgeInsets.only(bottom: 16),
              child: _PartEditor(
                part: _parts[i],
                canDelete: _parts.length > 1,
                onRename: () => _renamePart(i),
                onDelete: () => setState(() => _parts.removeAt(i)),
                onAddIngredient: () => _editIngredient(i),
                onEditIngredient: (index) => _editIngredient(i, index: index),
                onDeleteIngredient: (index) => _deleteIngredient(i, index),
                onAddStep: () => _editStep(i),
                onEditStep: (index) => _editStep(i, index: index),
                onDeleteStep: (index) => _deleteStep(i, index),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _buildPhotoSection() => _EditorSection(
    title: '料理の写真',
    icon: Icons.photo_outlined,
    children: [
      Semantics(
        button: true,
        enabled: !_choosingPhoto && !_saving,
        label: _photoPath == null ? '料理の写真を追加' : '料理の写真を変更',
        child: Material(
          color: mintSoft,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('manual_photo_area'),
            onTap: _choosingPhoto || _saving ? null : _choosePhoto,
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_photoPath == null)
                    const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          color: mossDeep,
                          size: 36,
                        ),
                        SizedBox(height: 10),
                        Text('完成した料理の写真を追加'),
                      ],
                    )
                  else
                    RecipeImage(path: _photoPath, cacheWidth: 800),
                  if (_choosingPhoto)
                    const ColoredBox(
                      color: Color(0x55000000),
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        '写真は1枚。容量を抑えて保存します。',
        style: TextStyle(fontSize: 12, color: secondaryInk),
      ),
      if (_photoPath != null)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _choosingPhoto || _saving
                ? null
                : () {
                    final oldDraft = _draftPhotoPath;
                    setState(() {
                      _photoPath = null;
                      _draftPhotoPath = null;
                    });
                    unawaited(_deleteDraft(oldDraft));
                  },
            child: const Text('写真を外す'),
          ),
        ),
    ],
  );

  Future<void> _choosePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('写真から選ぶ'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('カメラで撮る'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (!mounted || source == null) return;
    setState(() => _choosingPhoto = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (picked == null || !mounted) return;
      if (await picked.length() > 20 * 1024 * 1024) {
        throw const FormatException('画像の容量が大きすぎます。別の画像を選んでください。');
      }
      final path = await _photos.save(await picked.readAsBytes());
      if (!mounted) {
        await _deleteDraft(path);
        return;
      }
      final oldDraft = _draftPhotoPath;
      setState(() {
        _photoPath = path;
        _draftPhotoPath = path;
      });
      await _deleteDraft(oldDraft);
    } on PlatformException {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('写真・カメラへのアクセスを確認し、もう一度お試しください。')),
        );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message.toString()
                  : '写真を追加できませんでした。もう一度お試しください。',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _choosingPhoto = false);
    }
  }

  Future<void> _addPart() async {
    final name = await _askText('パートを追加', '例：タレ、出汁、トッピング');
    if (!mounted || name == null) return;
    setState(() => _parts.add(RecipePart(name: name)));
  }

  Future<void> _renamePart(int index) async {
    final current = _parts[index];
    final name = await _askText('パート名を編集', '例：本体、タレ', initial: current.name);
    if (!mounted || name == null) return;
    setState(
      () => _parts[index] = RecipePart(
        id: current.id,
        name: name,
        ingredients: current.ingredients,
        steps: current.steps,
      ),
    );
  }

  Future<String?> _askText(String title, String hint, {String? initial}) =>
      showDialog<String>(
        barrierDismissible: false,
        context: context,
        builder: (_) =>
            _NameEditorDialog(title: title, hint: hint, initial: initial),
      );

  Future<void> _editIngredient(int partIndex, {int? index}) async {
    final current = _parts[partIndex];
    final original = index == null ? null : current.ingredients[index];
    final ingredient = await showDialog<RecipeIngredient>(
      barrierDismissible: false,
      context: context,
      builder: (_) => _IngredientEditorDialog(original: original),
    );
    if (!mounted || ingredient == null) return;
    final ingredients = List<RecipeIngredient>.of(current.ingredients);
    if (index == null) {
      ingredients.add(ingredient);
    } else {
      ingredients[index] = ingredient;
    }
    setState(
      () => _parts[partIndex] = RecipePart(
        id: current.id,
        name: current.name,
        ingredients: ingredients,
        steps: current.steps,
      ),
    );
  }

  Future<void> _editStep(int partIndex, {int? index}) async {
    final current = _parts[partIndex];
    final original = index == null ? null : current.steps[index];
    final step = await showRecipeStepEditor(
      context,
      order: original?.order ?? current.steps.length + 1,
      original: original,
    );
    if (!mounted || step == null) return;
    final steps = List<RecipeStep>.of(current.steps);
    if (index == null) {
      steps.add(step);
    } else {
      steps[index] = step;
    }
    setState(
      () => _parts[partIndex] = RecipePart(
        id: current.id,
        name: current.name,
        ingredients: current.ingredients,
        steps: steps,
      ),
    );
  }

  void _deleteIngredient(int partIndex, int index) {
    final current = _parts[partIndex];
    final ingredients = List<RecipeIngredient>.of(current.ingredients)
      ..removeAt(index);
    final steps = current.steps
        .map(
          (step) => step.copyWith(
            ingredientIndexes: step.ingredientIndexes
                .where((i) => i != index)
                .map((i) => i > index ? i - 1 : i)
                .toList(),
          ),
        )
        .toList();
    setState(
      () => _parts[partIndex] = RecipePart(
        id: current.id,
        name: current.name,
        ingredients: ingredients,
        steps: steps,
      ),
    );
  }

  void _deleteStep(int partIndex, int index) {
    final current = _parts[partIndex];
    final steps = List<RecipeStep>.of(current.steps)..removeAt(index);
    setState(
      () => _parts[partIndex] = RecipePart(
        id: current.id,
        name: current.name,
        ingredients: current.ingredients,
        steps: steps
            .asMap()
            .entries
            .map((entry) => entry.value.copyWith(order: entry.key + 1))
            .toList(),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving || _choosingPhoto || _formKey.currentState?.validate() != true)
      return;
    final controller = RecipeScope.read(context);
    final original = _original;
    final sourcePostId = original?.sourcePostId ?? 'manual-${newId()}';
    final title = _title.text.trim();
    final description = _description.text.trim().isEmpty
        ? null
        : _description.text.trim();
    final servings = double.tryParse(_servings.text) ?? 2;
    final servingUnit = _servingUnit.text.trim().isEmpty
        ? '人分'
        : _servingUnit.text.trim();
    final totalMinutes = int.tryParse(_minutes.text);
    final category = _category.text.trim().isEmpty
        ? null
        : _category.text.trim();
    final editedFields = <String>{...?original?.userEditedFields};
    void track(String field, bool changed) {
      // 今回変更しなかった項目も、過去の編集済みフラグを保持する。
      if (changed) editedFields.add(field);
    }

    if (original != null) {
      track('coverImagePath', _photoPath != original.coverImagePath);
      track('title', title != original.title);
      track('description', description != original.description);
      track('servings', servings != original.servings);
      track('servingUnit', servingUnit != original.servingUnit);
      track('totalMinutes', totalMinutes != original.totalMinutes);
      track('category', category != original.category);
      track(
        'parts',
        jsonEncode(_parts.map((value) => value.toJson()).toList()) !=
            jsonEncode(original.parts.map((value) => value.toJson()).toList()),
      );
    }
    final recipe = Recipe(
      id: original?.id,
      sourcePostId: sourcePostId,
      title: title,
      description: description,
      servings: servings,
      servingUnit: servingUnit,
      totalMinutes: totalMinutes,
      category: category,
      parts: _parts,
      evidence: original?.evidence,
      coverImagePath: _photoPath,
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
      userEditedFields: editedFields,
      userNote: original?.userNote,
      nutrition: original?.nutrition,
      lastMadeAt: original?.lastMadeAt,
      madeCount: original?.madeCount ?? 0,
      createdAt: original?.createdAt,
    );
    setState(() => _saving = true);
    try {
      await controller.addManualRecipe(recipe);
      _photoCommitted = true;
      final previous = original?.coverImagePath;
      if (previous != null &&
          previous != _photoPath &&
          !controller.snapshot.recipes.any(
            (item) =>
                item.coverImagePath == previous ||
                item.evidence.any((evidence) => evidence.imagePath == previous),
          )) {
        await _deleteDraft(previous);
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('レシピを保存できませんでした。もう一度お試しください。')),
        );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      } else if (!_photoCommitted) {
        await _deleteDraft(_draftPhotoPath);
      }
    }
  }
}

class _EditorSection extends StatelessWidget {
  const _EditorSection({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: borderSubtle),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: mossDeep, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        ...children,
      ],
    ),
  );
}

class _PartEditor extends StatelessWidget {
  const _PartEditor({
    required this.part,
    required this.canDelete,
    required this.onRename,
    required this.onDelete,
    required this.onAddIngredient,
    required this.onEditIngredient,
    required this.onDeleteIngredient,
    required this.onAddStep,
    required this.onEditStep,
    required this.onDeleteStep,
  });
  final RecipePart part;
  final bool canDelete;
  final VoidCallback onRename, onDelete, onAddIngredient, onAddStep;
  final ValueChanged<int> onEditIngredient,
      onDeleteIngredient,
      onEditStep,
      onDeleteStep;
  @override
  Widget build(BuildContext context) => _EditorSection(
    title: part.name,
    icon: Icons.layers_outlined,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton.icon(
            onPressed: onRename,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('名前を変更'),
          ),
          if (canDelete)
            IconButton(
              tooltip: 'パートを削除',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      Text('材料', style: Theme.of(context).textTheme.titleMedium),
      if (part.ingredients.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('材料と分量を追加しましょう', style: TextStyle(color: secondaryInk)),
        ),
      for (var i = 0; i < part.ingredients.length; i++)
        ListTile(
          key: ValueKey(part.ingredients[i].id),
          contentPadding: EdgeInsets.zero,
          onTap: () => onEditIngredient(i),
          title: Text(part.ingredients[i].name),
          subtitle: Text(part.ingredients[i].quantityFor(1)),
          trailing: IconButton(
            tooltip: '材料を削除',
            onPressed: () => onDeleteIngredient(i),
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ),
      TextButton.icon(
        onPressed: onAddIngredient,
        icon: const Icon(Icons.add_rounded),
        label: const Text('材料を追加'),
      ),
      const Divider(height: 28),
      Text('作り方', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      const Text('工程をタップすると編集できます', style: TextStyle(color: secondaryInk)),
      if (part.steps.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('見出しと作り方を追加しましょう', style: TextStyle(color: secondaryInk)),
        ),
      for (var i = 0; i < part.steps.length; i++)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Material(
            color: mintSoft,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              key: ValueKey(part.steps[i].id),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              contentPadding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              onTap: () => onEditStep(i),
              leading: CircleAvatar(
                radius: 15,
                backgroundColor: mint,
                foregroundColor: mossDeep,
                child: Text('${i + 1}'),
              ),
              title: Text(
                part.steps[i].title?.trim().isNotEmpty == true
                    ? part.steps[i].title!
                    : 'STEP ${i + 1}',
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(part.steps[i].instruction),
              ),
              trailing: IconButton(
                tooltip: '工程を削除',
                onPressed: () => onDeleteStep(i),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ),
          ),
        ),
      TextButton.icon(
        onPressed: onAddStep,
        icon: const Icon(Icons.add_rounded),
        label: const Text('工程を追加'),
      ),
    ],
  );
}

Future<RecipeStep?> showRecipeStepEditor(
  BuildContext context, {
  required int order,
  RecipeStep? original,
}) => showDialog<RecipeStep>(
  barrierDismissible: false,
  context: context,
  builder: (_) => _StepEditorDialog(order: order, original: original),
);

class _InputDialog extends StatelessWidget {
  const _InputDialog({
    required this.title,
    required this.description,
    required this.icon,
    required this.content,
    required this.onSubmit,
    required this.submitLabel,
  });
  final String title, description, submitLabel;
  final IconData icon;
  final Widget content;
  final VoidCallback onSubmit;
  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    backgroundColor: Colors.white,
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
          child: Icon(icon, color: mossDeep),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
      ],
    ),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(description, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 18),
          content,
        ],
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
            child: FilledButton(onPressed: onSubmit, child: Text(submitLabel)),
          ),
        ],
      ),
    ],
  );
}

class _StepEditorDialog extends StatefulWidget {
  const _StepEditorDialog({required this.order, this.original});
  final int order;
  final RecipeStep? original;
  @override
  State<_StepEditorDialog> createState() => _StepEditorDialogState();
}

class _StepEditorDialogState extends State<_StepEditorDialog> {
  late final _title = TextEditingController(text: widget.original?.title ?? '');
  late final _instruction = TextEditingController(
    text: widget.original?.instruction ?? '',
  );
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _title.dispose();
    _instruction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _InputDialog(
    title: widget.original == null ? '工程を追加' : '工程を編集',
    description: 'STEP ${widget.order} の見出しと、具体的な作り方を入力してください。',
    icon: Icons.format_list_numbered_rounded,
    submitLabel: widget.original == null ? '追加' : '保存',
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            key: const ValueKey('step_title'),
            controller: _title,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '工程の見出し（任意）',
              hintText: '例：材料を切る',
            ),
          ),
          const SizedBox(height: 18),
          TextFormField(
            key: const ValueKey('step_instruction'),
            controller: _instruction,
            minLines: 4,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              labelText: '作り方',
              hintText: '例：鶏肉を一口大に切り、片栗粉をまぶす。',
              alignLabelWithHint: true,
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            validator: (value) =>
                value?.trim().isEmpty != false ? '作り方を入力してください' : null,
          ),
        ],
      ),
    ),
    onSubmit: () {
      if (_form.currentState?.validate() != true) return;
      final original = widget.original;
      Navigator.pop(
        context,
        original == null
            ? RecipeStep(
                order: widget.order,
                title: _title.text.trim(),
                instruction: _instruction.text.trim(),
                userEdited: true,
              )
            : original.copyWith(
                title: _title.text.trim(),
                instruction: _instruction.text.trim(),
                userEdited: true,
              ),
      );
    },
  );
}

class _IngredientEditorDialog extends StatefulWidget {
  const _IngredientEditorDialog({this.original});
  final RecipeIngredient? original;
  @override
  State<_IngredientEditorDialog> createState() =>
      _IngredientEditorDialogState();
}

class _IngredientEditorDialogState extends State<_IngredientEditorDialog> {
  late final _name = TextEditingController(text: widget.original?.name ?? '');
  late final _quantity = TextEditingController(
    text: widget.original?.quantityFor(1) ?? '',
  );
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _InputDialog(
    title: widget.original == null ? '材料を追加' : '材料を編集',
    description: '材料名と分量を分けて入力してください。',
    icon: Icons.kitchen_outlined,
    submitLabel: widget.original == null ? '追加' : '保存',
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '材料名',
              hintText: '例：鶏もも肉',
            ),
            validator: (value) =>
                value?.trim().isEmpty != false ? '材料名を入力してください' : null,
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _quantity,
            decoration: const InputDecoration(
              labelText: '分量',
              hintText: '例：250g、大さじ1、少々',
            ),
          ),
        ],
      ),
    ),
    onSubmit: () {
      if (_form.currentState?.validate() != true) return;
      final original = widget.original;
      Navigator.pop(
        context,
        RecipeIngredient(
          id: original?.id,
          name: _name.text.trim(),
          originalText: _quantity.text.trim(),
          scalable: true,
          note: original?.note,
          evidenceId: original?.evidenceId,
          confidencePercent: original?.confidencePercent,
          userEdited: true,
        ),
      );
    },
  );
}

class _NameEditorDialog extends StatefulWidget {
  const _NameEditorDialog({
    required this.title,
    required this.hint,
    this.initial,
  });
  final String title, hint;
  final String? initial;
  @override
  State<_NameEditorDialog> createState() => _NameEditorDialogState();
}

class _NameEditorDialogState extends State<_NameEditorDialog> {
  late final _name = TextEditingController(text: widget.initial ?? '');
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _InputDialog(
    title: widget.title,
    description: '材料や工程をまとめる名前を入力してください。',
    icon: Icons.layers_outlined,
    submitLabel: '保存',
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _name,
        decoration: InputDecoration(labelText: 'パート名', hintText: widget.hint),
        validator: (value) =>
            value?.trim().isEmpty != false ? '名前を入力してください' : null,
      ),
    ),
    onSubmit: () {
      if (_form.currentState?.validate() == true) {
        Navigator.pop(context, _name.text.trim());
      }
    },
  );
}
