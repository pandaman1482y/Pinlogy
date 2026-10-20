import 'dart:convert';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../models/recipe_models.dart';
import '../recipe_controller.dart';
import '../recipe_scope.dart';
import '../services/recipe_assistant_service.dart';
import 'recipe_detail_page.dart';
import 'recipe_widgets.dart';

class RecipeAiPage extends StatefulWidget {
  const RecipeAiPage({super.key, this.assistant});

  final RecipeAssistantService? assistant;

  @override
  State<RecipeAiPage> createState() => _RecipeAiPageState();
}

class _RecipeAiPageState extends State<RecipeAiPage> {
  final _query = TextEditingController();
  final _queryFocus = FocusNode();
  final _scroll = ScrollController();
  late final _assistant = widget.assistant ?? RecipeAssistantService();
  RecipeAssistantAnswer? _answer;
  String? _answerPreferenceKey;
  bool _loading = false;

  @override
  void dispose() {
    _assistant.dispose();
    _query.dispose();
    _queryFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = RecipeScope.of(context);
    final preferenceKey = jsonEncode(
      controller.snapshot.allergySettings.toJson(),
    );
    final answer = _answerPreferenceKey == preferenceKey ? _answer : null;
    final matches =
        answer?.savedRecipeIds
            .map(controller.recipeById)
            .whereType<Recipe>()
            .toList() ??
        const <Recipe>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('AIに相談'),
        actions: [
          IconButton(
            tooltip: 'キーボードを閉じる',
            onPressed: () => FocusScope.of(context).unfocus(),
            icon: const Icon(Icons.keyboard_hide_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxHeight < 420 ||
              MediaQuery.viewInsetsOf(context).bottom > 0;
          return Column(
            children: [
              Material(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('ai_query_input'),
                        controller: _query,
                        focusNode: _queryFocus,
                        onTapOutside: (_) => _queryFocus.unfocus(),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _ask(controller),
                        minLines: 1,
                        maxLines: compact ? 1 : 3,
                        decoration: InputDecoration(
                          labelText: '質問・検索',
                          hintText: '例：鶏むね肉とキャベツで何が作れる？',
                          suffixIcon: IconButton(
                            tooltip: '質問を送信',
                            onPressed: _loading ? null : () => _ask(controller),
                            icon: const Icon(Icons.arrow_upward_rounded),
                          ),
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _loading ? null : () => _ask(controller),
                            icon: const Icon(
                              Icons.auto_awesome_rounded,
                              size: 18,
                            ),
                            label: Text(_loading ? '考えています…' : '提案してもらう'),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final prompt in const [
                                '最近作っていないもの',
                                '15分で作れるもの',
                                '野菜を使いたい',
                                'お気に入りから',
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ActionChip(
                                    label: Text(prompt),
                                    onPressed: _loading
                                        ? null
                                        : () {
                                            _query.text = prompt;
                                            _ask(controller);
                                          },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  key: const ValueKey('ai_answer_list'),
                  controller: _scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  children: [
                    if (answer == null && !_loading) ...[
                      Text(
                        '保存したレシピから探します',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _answer != null
                            ? '食材の設定が変わりました。新しい設定で、もう一度質問してください。'
                            : '家にある材料、最近作ったもの、食べたい気分を入力してください。質問欄は回答を読んでいる間も上部に表示されます。',
                      ),
                    ],
                    if (answer != null) ...[
                      const SizedBox(height: 28),
                      Text(
                        'AIの回答',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        answer!.message,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      if (answer!.warning != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          answer!.warning!,
                          style: const TextStyle(
                            color: warningColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      if (matches.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Text(
                              '保存済みから',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
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
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              leading: SizedBox(
                                width: 58,
                                height: 58,
                                child: RecipeImage(
                                  path: recipe.coverImagePath,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              title: Text(recipe.title),
                              subtitle: Text(
                                compactDuration(recipe.totalMinutes),
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      RecipeDetailPage(recipeId: recipe.id),
                                ),
                              ),
                            ),
                          ),
                      ],
                      if (answer!.newSuggestions.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Text(
                              '新しい提案',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(width: 8),
                            const Chip(label: Text('未保存')),
                          ],
                        ),
                        const SizedBox(height: 6),
                        for (final suggestion in answer!.newSuggestions)
                          ListTile(
                            leading: const Icon(
                              Icons.lightbulb_outline_rounded,
                              color: mossDeep,
                            ),
                            title: Text(suggestion),
                            subtitle: const Text('新しいレシピ候補。保存済みの内容ではありません。'),
                          ),
                      ],
                      const SizedBox(height: 18),
                      Text(
                        'アレルギー設定を考慮しますが、材料の抽出漏れや製品由来の混入を完全には判定できません。必ず元投稿と商品表示をご確認ください。',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: secondaryInk),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _ask(RecipeController controller) async {
    final query = _query.text.trim();
    if (query.isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    final settings = controller.snapshot.allergySettings;
    final preferenceKey = jsonEncode(settings.toJson());
    try {
      final answer = await _assistant.ask(
        query: query,
        recipes: controller.savedRecipes,
        allergySettings: settings,
      );
      if (!mounted) return;
      setState(() {
        _answer = answer;
        _answerPreferenceKey = preferenceKey;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _answer = const RecipeAssistantAnswer(
          message: '回答を取得できませんでした。通信状態を確認して、もう一度お試しください。',
        );
        _answerPreferenceKey = preferenceKey;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }
}
