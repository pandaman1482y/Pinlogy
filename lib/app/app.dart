import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../recipe/recipe_scope.dart';
import '../recipe/ui/recipe_ai_page.dart';
import '../recipe/ui/recipe_home_page.dart';
import '../recipe/ui/recipe_profile_page.dart';
import '../recipe/ui/recipe_search_page.dart';
import '../recipe/ui/recipe_detail_page.dart';
import '../recipe/ui/recipe_selection_page.dart';
import '../services/ai_analysis_consent.dart';
import '../services/notification_service.dart';

class PinlogyApp extends StatelessWidget {
  const PinlogyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'レシピ',
    theme: buildPinlogyTheme(),
    darkTheme: buildPinlogyTheme(),
    themeMode: ThemeMode.light,
    home: const RecipeBootstrapScreen(),
  );
}

class RecipeBootstrapScreen extends StatefulWidget {
  const RecipeBootstrapScreen({super.key});

  @override
  State<RecipeBootstrapScreen> createState() => _RecipeBootstrapScreenState();
}

class _RecipeBootstrapScreenState extends State<RecipeBootstrapScreen> {
  bool _checkedConsent = false;

  @override
  Widget build(BuildContext context) {
    final controller = RecipeScope.of(context);
    if (controller.loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text('レシピを準備しています…'),
            ],
          ),
        ),
      );
    }
    if (controller.loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 46, color: errorColor),
                const SizedBox(height: 12),
                Text('起動に失敗しました', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(controller.loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: controller.initialize, child: const Text('再試行')),
              ],
            ),
          ),
        ),
      );
    }
    if (!_checkedConsent) {
      _checkedConsent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _askConsentIfNeeded());
    }
    return const RecipeRootShell();
  }

  Future<void> _askConsentIfNeeded() async {
    final consent = AiAnalysisConsent();
    if (!mounted || await consent.hasMadeChoice()) return;
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.auto_awesome_rounded, color: mossDeep),
        title: const Text('SNS投稿をレシピに整理'),
        content: const Text(
          '投稿文・共有画像・動画内の文字などをAI解析へ送信し、材料と工程に整理します。端末の個人写真や保存済みレシピを無断で送信することはありません。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('今は使わない')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('同意して使う')),
        ],
      ),
    );
    await consent.setConsented(accepted == true);
  }
}

class RecipeRootShell extends StatefulWidget {
  const RecipeRootShell({super.key});

  @override
  State<RecipeRootShell> createState() => _RecipeRootShellState();
}

class _RecipeRootShellState extends State<RecipeRootShell> {
  int _index = 0;
  StreamSubscription<String?>? _notificationSubscription;

  static const _pages = [
    RecipeHomePage(),
    RecipeSearchPage(),
    RecipeAiPage(),
    RecipeProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    final notifications = PinlogyNotificationService.instance;
    _notificationSubscription = notifications.completionSourcePostIds.listen(
      _openCompletedImport,
    );
    final initial = notifications.consumeInitialCompletionSourcePostId();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openCompletedImport(initial));
    }
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _openCompletedImport(String? sourcePostId) async {
    if (!mounted) return;
    setState(() => _index = 0);
    final controller = RecipeScope.read(context);
    await controller.syncFromIntake();
    if (!mounted || sourcePostId == null || sourcePostId.isEmpty) return;
    final item = controller.snapshot.imports
        .where((value) => value.sourcePostId == sourcePostId)
        .firstOrNull;
    if (item == null) return;
    if (item.requiresSelection) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => RecipeSelectionPage(importId: item.id)),
      );
      return;
    }
    final recipe = controller.recipesForImport(item).where((value) => value.isSaved).firstOrNull;
    if (recipe != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => RecipeDetailPage(recipeId: recipe.id)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _index, children: _pages),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (value) => setState(() => _index = value),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.auto_stories_outlined), selectedIcon: Icon(Icons.auto_stories_rounded), label: 'レシピ'),
        NavigationDestination(icon: Icon(Icons.search_rounded), label: '検索'),
        NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome_rounded), label: 'AI'),
        NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'マイページ'),
      ],
    ),
  );
}
