import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import '../recipe/recipe_scope.dart';
import '../recipe/ui/billing_page.dart';
import '../recipe/ui/recipe_ai_page.dart';
import '../recipe/ui/recipe_home_page.dart';
import '../recipe/ui/recipe_profile_page.dart';
import '../recipe/ui/recipe_search_page.dart';
import '../recipe/ui/recipe_detail_page.dart';
import '../recipe/ui/recipe_selection_page.dart';
import '../services/ai_analysis_consent.dart';
import '../services/cloud_sync_service.dart';
import '../services/notification_service.dart';
import '../services/share_receiver_service.dart';

class PinlogyApp extends StatelessWidget {
  const PinlogyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'ツクレピ',
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
  static const _loginPromptKey = 'tsukurepi_login_prompt_v1_completed';

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
                const Icon(
                  Icons.error_outline_rounded,
                  size: 46,
                  color: errorColor,
                ),
                const SizedBox(height: 12),
                Text(
                  '起動に失敗しました',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(controller.loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: controller.initialize,
                  child: const Text('再試行'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!_checkedConsent) {
      _checkedConsent = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _runFirstLaunchFlow(),
      );
    }
    return const RecipeRootShell();
  }

  Future<void> _runFirstLaunchFlow() async {
    await _askConsentIfNeeded();
    if (!mounted) return;
    await _showLoginPromptIfNeeded();
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
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('今は使わない'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('同意して使う'),
          ),
        ],
      ),
    );
    await consent.setConsented(accepted == true);
  }

  Future<void> _showLoginPromptIfNeeded() async {
    final controller = RecipeScope.read(context);
    final cloud = controller.legacy.cloud;
    if (!cloud.isConfigured) return;
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_loginPromptKey) == true || !mounted) return;
    try {
      await cloud.prepareAuth();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final current = cloud.user;
    if (current != null && !current.isAnonymous) {
      await preferences.setBool(_loginPromptKey, true);
      return;
    }

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  child: CircleAvatar(
                    radius: 27,
                    backgroundColor: mintSoft,
                    child: Icon(
                      Icons.cloud_done_outlined,
                      color: mossDeep,
                      size: 29,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'レシピを安全に引き継ぐ',
                  textAlign: TextAlign.center,
                  style: Theme.of(dialogContext).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  'ログインすると保存したレシピを同期し、機種変更後も引き継げます。',
                  textAlign: TextAlign.center,
                  style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, 'apple'),
                    icon: const Icon(Icons.apple, size: 24),
                    label: const Text('Appleで続ける'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, 'google'),
                    icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                    label: const Text('Googleで続ける'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(
                        dialogContext,
                      ).colorScheme.onSurface,
                      side: BorderSide(
                        color: Theme.of(
                          dialogContext,
                        ).colorScheme.outlineVariant,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, 'later'),
                  child: const Text('今はしない'),
                ),
                Text(
                  'ログインしなくても、端末内で引き続き利用できます。',
                  textAlign: TextAlign.center,
                  style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'later') {
      await preferences.setBool(_loginPromptKey, true);
      return;
    }

    try {
      if (action == 'apple') {
        await cloud.signInWithApple();
      } else {
        await cloud.signInWithGoogle();
      }
      await preferences.setBool(_loginPromptKey, true);
      if (mounted && cloud.user != null && cloud.user?.isAnonymous != true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ログインしました。レシピを同期します。')));
      }
    } on CloudSignInCancelled {
      // キャンセルは失敗表示にせず、次回起動時にもう一度案内できるようにする。
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ログインできませんでした: $error')));
    }
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
  StreamSubscription<DuplicateShareEvent>? _duplicateSubscription;
  StreamSubscription<AnalysisFailureEvent>? _failureSubscription;
  bool _duplicateDialogVisible = false;
  bool _failureDialogVisible = false;
  final List<DuplicateShareEvent> _pendingDuplicateEvents = [];
  final List<AnalysisFailureEvent> _pendingFailureEvents = [];
  final Set<String> _shownFailureJobIds = {};

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
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openCompletedImport(initial),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _duplicateSubscription ??= RecipeScope.read(
      context,
    ).legacy.shareIntake.onDuplicate.listen(_enqueueDuplicateShare);
    _failureSubscription ??= analysisFailureEvents.listen(
      _enqueueAnalysisFailure,
    );
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _duplicateSubscription?.cancel();
    _failureSubscription?.cancel();
    super.dispose();
  }

  void _enqueueDuplicateShare(DuplicateShareEvent event) {
    final alreadyQueued = _pendingDuplicateEvents.any(
      (value) => value.post.id == event.post.id,
    );
    if (!alreadyQueued) _pendingDuplicateEvents.add(event);
    if (!_duplicateDialogVisible && !_failureDialogVisible) {
      unawaited(_drainDuplicateShares());
    }
  }

  Future<void> _drainDuplicateShares() async {
    _duplicateDialogVisible = true;
    try {
      while (mounted && _pendingDuplicateEvents.isNotEmpty) {
        final event = _pendingDuplicateEvents.removeAt(0);
        await _showDuplicateShare(event);
      }
    } finally {
      _duplicateDialogVisible = false;
      if (mounted && _pendingFailureEvents.isNotEmpty) {
        unawaited(_drainAnalysisFailures());
      }
    }
  }

  void _enqueueAnalysisFailure(AnalysisFailureEvent event) {
    if (!_shownFailureJobIds.add(event.jobId)) return;
    _pendingFailureEvents.add(event);
    if (!_failureDialogVisible && !_duplicateDialogVisible) {
      unawaited(_drainAnalysisFailures());
    }
  }

  Future<void> _drainAnalysisFailures() async {
    _failureDialogVisible = true;
    try {
      while (mounted && _pendingFailureEvents.isNotEmpty) {
        await _showAnalysisFailure(_pendingFailureEvents.removeAt(0));
      }
    } finally {
      _failureDialogVisible = false;
      if (mounted && _pendingDuplicateEvents.isNotEmpty) {
        unawaited(_drainDuplicateShares());
      }
    }
  }

  Future<void> _showAnalysisFailure(AnalysisFailureEvent event) async {
    if (!mounted) return;
    final title = event.creditsExhausted
        ? '解析回数が足りません'
        : event.blocked
        ? 'この投稿は登録できません'
        : event.recipeNotFound
        ? 'レシピを確認できませんでした'
        : '解析に失敗しました';
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(event.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
          if (event.creditsExhausted)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'billing'),
              child: const Text('利用プランを見る'),
            )
          else if (!event.blocked)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'progress'),
              child: const Text('取り込み状況を見る'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'billing') {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const BillingPage()));
    } else if (action == 'progress') {
      setState(() => _index = 0);
    }
  }

  Future<void> _showDuplicateShare(DuplicateShareEvent event) async {
    if (!mounted) return;
    final controller = RecipeScope.read(context);
    await controller.syncFromIntake();
    if (!mounted) return;
    final item = controller.snapshot.imports
        .where((value) => value.sourcePostId == event.post.id)
        .firstOrNull;
    final saved = item == null
        ? null
        : controller
              .recipesForImport(item)
              .where((value) => value.isSaved)
              .firstOrNull;
    final failed =
        event.job?.status.name == 'failed' ||
        event.job?.status.name == 'cancelled';
    final title = saved != null
        ? 'この投稿は保存済みです'
        : failed
        ? 'この投稿は前回解析できませんでした'
        : event.job?.status.name == 'pending'
        ? 'この投稿は解析待ちです'
        : 'この投稿は現在解析中です';
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(
          saved != null
              ? '新しい解析や回数消費は行いません。'
              : failed
              ? '共有しただけでは再試行しません。'
              : '既存の解析状況を表示します。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
          if (saved != null)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'open'),
              child: const Text('レシピを見る'),
            )
          else if (failed && item != null)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'retry'),
              child: const Text('再試行'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'progress'),
              child: const Text('進捗を見る'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'open' && saved != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RecipeDetailPage(recipeId: saved.id),
        ),
      );
    } else if (action == 'retry' && item != null) {
      await controller.retryImport(item);
    } else if (action == 'progress') {
      setState(() => _index = 0);
    }
  }

  Future<void> _openCompletedImport(String? sourcePostId) async {
    if (!mounted) return;
    setState(() => _index = 0);
    final controller = RecipeScope.read(context);
    await controller.refreshCompletedImport(sourcePostId);
    if (!mounted || sourcePostId == null || sourcePostId.isEmpty) return;
    final item = controller.snapshot.imports
        .where((value) => value.sourcePostId == sourcePostId)
        .firstOrNull;
    if (item == null) return;
    if (item.requiresSelection) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RecipeSelectionPage(importId: item.id),
        ),
      );
      return;
    }
    final recipe = controller
        .recipesForImport(item)
        .where((value) => value.isSaved)
        .firstOrNull;
    if (recipe != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RecipeDetailPage(recipeId: recipe.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _index, children: _pages),
    bottomNavigationBar: NavigationBar(
      height: 58,
      selectedIndex: _index,
      onDestinationSelected: (value) => setState(() => _index = value),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.auto_stories_outlined),
          selectedIcon: Icon(Icons.auto_stories_rounded),
          label: 'レシピ',
        ),
        NavigationDestination(icon: Icon(Icons.search_rounded), label: '検索'),
        NavigationDestination(
          icon: Icon(Icons.auto_awesome_outlined),
          selectedIcon: Icon(Icons.auto_awesome_rounded),
          label: 'AI',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: 'マイページ',
        ),
      ],
    ),
  );
}
