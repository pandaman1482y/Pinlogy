import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../models/recipe_models.dart';
import '../recipe_controller.dart';
import '../recipe_scope.dart';
import '../services/recipe_assistant_service.dart';
import 'recipe_detail_page.dart';
import 'recipe_widgets.dart';

class RecipeAiPage extends StatefulWidget {
  const RecipeAiPage({super.key});

  @override
  State<RecipeAiPage> createState() => _RecipeAiPageState();
}

class _RecipeAiPageState extends State<RecipeAiPage> {
  final _query = TextEditingController();
  final _assistant = RecipeAssistantService();
  RecipeAssistantAnswer? _answer;
  bool _loading = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = RecipeScope.of(context);
    final matches = _answer?.savedRecipeIds
            .map(controller.recipeById)
            .whereType<Recipe>()
            .toList() ??
        const <Recipe>[];
    return Scaffold(
      appBar: AppBar(title: const Text('AIに相談')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          SoftPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: mint,
                      child: Icon(Icons.auto_awesome_rounded, color: mossDeep),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('保存したレシピから探します', style: Theme.of(context).textTheme.titleLarge),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '家にある材料、最近作ったもの、食べたい気分を自然な言葉で入力できます。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: secondaryInk),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _query,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: '例：鶏むね肉とキャベツがある。30分以内で何が作れる？',
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : () => _ask(controller),
                    icon: _loading
                        ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.arrow_upward_rounded),
                    label: Text(_loading ? '考えています…' : '提案してもらう'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final prompt in const ['最近作っていないもの', '15分で作れるもの', '野菜を使いたい', 'お気に入りから'])
                ActionChip(
                  label: Text(prompt),
                  onPressed: () {
                    _query.text = prompt;
                    _ask(controller);
                  },
                ),
            ],
          ),
          if (_answer != null) ...[
            const SizedBox(height: 28),
            Text('AIの回答', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 10),
            Text(_answer!.message, style: Theme.of(context).textTheme.bodyLarge),
            if (_answer!.warning != null) ...[
              const SizedBox(height: 10),
              Text(_answer!.warning!, style: const TextStyle(color: warningColor, fontWeight: FontWeight.w700)),
            ],
            if (matches.isNotEmpty) ...[
              const SizedBox(height: 22),
              Row(
                children: [
                  Text('保存済みから', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(width: 8),
                  const Chip(label: Text('ライブラリ')),
                ],
              ),
              const SizedBox(height: 10),
              for (final recipe in matches)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(8),
                    tileColor: mintSoft,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    leading: SizedBox(
                      width: 58,
                      height: 58,
                      child: RecipeImage(path: recipe.coverImagePath, borderRadius: BorderRadius.circular(10)),
                    ),
                    title: Text(recipe.title),
                    subtitle: Text(compactDuration(recipe.totalMinutes)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => RecipeDetailPage(recipeId: recipe.id)),
                    ),
                  ),
                ),
            ],
            if (_answer!.newSuggestions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('新しい提案', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(width: 8),
                  const Chip(label: Text('未保存')),
                ],
              ),
              const SizedBox(height: 6),
              for (final suggestion in _answer!.newSuggestions)
                ListTile(
                  leading: const Icon(Icons.lightbulb_outline_rounded, color: mossDeep),
                  title: Text(suggestion),
                  subtitle: const Text('新しいレシピ候補。保存済みの内容ではありません。'),
                ),
            ],
            const SizedBox(height: 18),
            Text(
              'アレルギー設定を考慮しますが、材料の抽出漏れや製品由来の混入を完全には判定できません。必ず元投稿と商品表示をご確認ください。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: secondaryInk),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _ask(RecipeController controller) async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    setState(() => _loading = true);
    final answer = await _assistant.ask(
      query: query,
      recipes: controller.savedRecipes,
      allergySettings: controller.snapshot.allergySettings,
    );
    if (!mounted) return;
    setState(() {
      _answer = answer;
      _loading = false;
    });
  }
}
