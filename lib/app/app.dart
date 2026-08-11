import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../core/theme.dart';
import '../features/inbox/inbox_tab.dart';
import '../features/maps/maps_tab.dart';
import '../features/onboarding/onboarding_sheet.dart';
import '../features/profile/profile_tab.dart';
import '../features/settings/cloud_sync_page.dart';
import '../models/models.dart';
import '../widgets/common_widgets.dart';
import '../widgets/map_tiles.dart';
import '../widgets/place_photo.dart';
import '../widgets/sheet_layout.dart';
import '../widgets/source_post_tile.dart';

class PinlogyApp extends StatelessWidget {
  const PinlogyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pinlogy',
      theme: buildPinlogyTheme(),
      home: const BootstrapScreen(),
    );
  }
}

class BootstrapScreen extends StatelessWidget {
  const BootstrapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    if (controller.loading) {
      return const PinlogyBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: LoadingView(message: 'Pinlogy を準備中…'),
        ),
      );
    }
    if (controller.loadError != null) {
      return PinlogyBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: EmptyState(
            icon: Icons.error_outline,
            title: '起動に失敗しました',
            message: controller.loadError!,
            action: FilledButton(
              onPressed: controller.initialize,
              child: const Text('再試行'),
            ),
          ),
        ),
      );
    }
    return const HomeScreen();
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int index = 0;
  StreamSubscription<SourcePost>? _shareSub;
  StreamSubscription<Uri>? _linkSub;
  Timer? _onboardingTimer;
  final AppLinks _appLinks = AppLinks();
  String? _handledShareCode;
  bool _checkingQuotaNotice = false;
  bool _quotaDialogOpen = false;
  final List<SourcePost> _queuedSharePrompts = [];
  bool _drainingSharePrompts = false;
  BuildContext? _activeShareDialogContext;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = AppScope.read(context);
      unawaited(_listenForMapShares());
      // 共有起動直後は投稿受信を優先し、チュートリアルとの二重表示を防ぐ。
      _onboardingTimer = Timer(const Duration(milliseconds: 800), () {
        if (!mounted || controller.hub.snapshot.sourcePosts.isNotEmpty) return;
        unawaited(_showFirstRunGuidance());
      });
      // 個人の保存座標は送信せず、日本全体の共通タイルと接続だけ先に温める。
      unawaited(
        PinlogyMapTiles.preloadAround(
          context,
          latitude: 36.4,
          longitude: 138.0,
          zoom: 5.2,
        ),
      );
      _shareSub = controller.shareIntake.onSaved.listen((post) {
        controller.acknowledgeSharedPost(post.id);
        _enqueueSharePrompt(post);
      });
      final pendingPosts = controller.consumePendingSharedPosts();
      for (final post in pendingPosts) {
        _enqueueSharePrompt(post);
      }
      final pending = controller.consumeShareToast();
      if (pending != null && pendingPosts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text(pending),
            action: SnackBarAction(
              label: '受信箱',
              textColor: leafWash,
              onPressed: () => _selectTab(1),
            ),
          ),
        );
      }
    });
  }

  void _enqueueSharePrompt(SourcePost post) {
    _queuedSharePrompts.add(post);
    final dialogContext = _activeShareDialogContext;
    if (dialogContext != null && Navigator.of(dialogContext).canPop()) {
      Navigator.pop(dialogContext, '');
    }
    unawaited(_drainSharePrompts());
  }

  Future<void> _drainSharePrompts() async {
    if (_drainingSharePrompts) return;
    _drainingSharePrompts = true;
    try {
      while (mounted && _queuedSharePrompts.isNotEmpty) {
        final post = _queuedSharePrompts.removeAt(0);
        // さらに共有が待っている場合は先頭をメモなしで確定し、最後の1件だけ入力を待つ。
        if (_queuedSharePrompts.isNotEmpty) {
          await AppScope.read(context).analyzeSharedPost(post);
          continue;
        }
        await _promptForSharedPost(post);
      }
    } finally {
      _drainingSharePrompts = false;
    }
  }

  Future<void> _showFirstRunGuidance() async {
    await showOnboardingIfNeeded(context);
    if (!mounted) return;
    await showAiAnalysisConsentIfNeeded(context);
  }

  Future<void> _promptForSharedPost(SourcePost post) async {
    if (!mounted) return;
    _onboardingTimer?.cancel();
    setState(() => index = 1);
    await showAiAnalysisConsentIfNeeded(context);
    if (!mounted) return;
    final controller = AppScope.read(context);
    var displayPost = await controller.sourcePosts.getById(post.id) ?? post;
    if (displayPost.imagePaths.isEmpty && displayPost.url != null) {
      try {
        displayPost = await controller.shareReceiver.refreshOfficialPreview(
          displayPost,
        );
      } catch (_) {
        // サムネイル取得に失敗してもURLとメモ入力で取り込みを続ける。
      }
    }
    if (!mounted) return;
    if (_queuedSharePrompts.isNotEmpty) {
      await controller.analyzeSharedPost(displayPost);
      return;
    }
    final memoController = TextEditingController();
    String? memo;
    try {
      memo = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          _activeShareDialogContext = dialogContext;
          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            icon: const Icon(Icons.edit_note_rounded),
            title: const Text('取り込みメモ'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (displayPost.imagePaths.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: PlacePhoto(
                            path: displayPost.imagePaths.first,
                            fallback: const ColoredBox(
                              color: Color(0xFFE8F1EC),
                              child: Center(
                                child: Icon(Icons.movie_outlined, size: 36),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SourcePostTile(post: displayPost, compact: true),
                    const SizedBox(height: 16),
                    TextField(
                      controller: memoController,
                      autofocus: true,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: '店名や住所など（任意）',
                        helperText: '入力すると場所を検索しやすくなります',
                        helperMaxLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, ''),
                child: const Text('メモなしで追加'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, memoController.text),
                child: const Text('追加して検索'),
              ),
            ],
          );
        },
      );
    } finally {
      _activeShareDialogContext = null;
      disposeAfterFrame([memoController]);
    }
    if (!mounted || memo == null) return;
    await AppScope.read(context).analyzeSharedPost(displayPost, memo: memo);
    if (!mounted) return;
    final message = AppScope.read(context).consumeShareToast() ?? '受信箱に保存しました';
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(message),
      ),
    );
  }

  Future<void> _listenForMapShares() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) await _handleLink(initial);
      _linkSub ??= _appLinks.uriLinkStream.listen((uri) {
        unawaited(_handleLink(uri));
      });
    } catch (_) {
      // リンク受信に失敗しても通常起動と共有コード手入力は利用できる。
    }
  }

  Future<void> _handleLink(Uri uri) async {
    if (!mounted || uri.scheme != 'pinlogy' || uri.host != 'map-share') return;
    final code = uri.queryParameters['code']?.trim();
    if (code == null || code.isEmpty || code == _handledShareCode) return;
    _handledShareCode = code;
    _onboardingTimer?.cancel();
    final open = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.map_outlined),
        title: const Text('共有マップを受け取りますか？'),
        content: const Text(
          '内容を確認して、自分のPinlogyに追加できます。ログインしていない場合は先にアカウント設定が必要です。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('あとで'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('確認する'),
          ),
        ],
      ),
    );
    if (!mounted || open != true) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CloudSyncPage(initialShareCode: code),
      ),
    );
  }

  void _selectTab(int value) {
    if (!mounted) return;
    setState(() => index = value);
  }

  Future<void> _showQuotaNoticeIfNeeded() async {
    if (!mounted || _checkingQuotaNotice || _quotaDialogOpen) return;
    _checkingQuotaNotice = true;
    try {
      final shouldShow = await AppScope.read(context).consumeAiQuotaNotice();
      if (!mounted || !shouldShow) return;
      _quotaDialogOpen = true;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.auto_awesome_outlined),
          title: const Text('本日のAI取り込みは終了しました'),
          content: const Text(
            '1日10回のAI取り込み上限に達しました。\n\n'
            '明日になると自動で再開します。それまでも端末内の簡易解析、手動登録、地図検索、ピン追加はご利用いただけます。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('わかりました'),
            ),
          ],
        ),
      );
    } finally {
      _checkingQuotaNotice = false;
      _quotaDialogOpen = false;
    }
  }

  @override
  void dispose() {
    _onboardingTimer?.cancel();
    _shareSub?.cancel();
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badge = AppScope.of(context).inboxBadgeCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showQuotaNoticeIfNeeded());
    });
    return PinlogyBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: index,
            children: const [MapsTab(), InboxTab(), ProfileTab()],
          ),
        ),
        bottomNavigationBar: PinlogyPillNav(
          index: index,
          inboxBadge: badge,
          onChanged: _selectTab,
        ),
      ),
    );
  }
}
