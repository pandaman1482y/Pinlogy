import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app/app_scope.dart';
import '../core/theme.dart';
import '../features/inbox/inbox_tab.dart';
import '../features/maps/maps_tab.dart';
import '../features/onboarding/onboarding_sheet.dart';
import '../features/plans/plans_tab.dart';
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
    // 解析画像の選択中に次の共有が届いても、現在のダイアログを閉じない。
    // 閉じると未選択のまま旧自動解析ルートへ流れるため、順番に確認する。
    unawaited(_drainSharePrompts());
  }

  Future<void> _drainSharePrompts() async {
    if (_drainingSharePrompts) return;
    _drainingSharePrompts = true;
    final controller = AppScope.read(context);
    try {
      while (mounted && _queuedSharePrompts.isNotEmpty) {
        final post = _queuedSharePrompts.removeAt(0);
        // さらに共有が待っている場合は先頭をメモなしで確定し、最後の1件だけ入力を待つ。
        if (_queuedSharePrompts.isNotEmpty && !_requiresImageSelection(post)) {
          await controller.analyzeSharedPost(post);
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
    final shouldRefreshSocialImages =
        displayPost.url != null &&
        (displayPost.imagePaths.isEmpty ||
            displayPost.service == 'Instagram' ||
            displayPost.service == 'TikTok');
    if (shouldRefreshSocialImages) {
      try {
        displayPost = await controller.shareReceiver.refreshOfficialPreview(
          displayPost,
          force: true,
        );
      } catch (_) {
        // サムネイル取得に失敗してもURLとメモ入力で取り込みを続ける。
      }
    }
    if (!mounted) return;
    if (_queuedSharePrompts.isNotEmpty &&
        !_requiresImageSelection(displayPost)) {
      await controller.analyzeSharedPost(displayPost);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final memoController = TextEditingController();
    final selectedImagePaths = <String>{};
    String? memo;
    try {
      memo = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          _activeShareDialogContext = dialogContext;
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
              scrollable: true,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              icon: const Icon(Icons.edit_note_rounded),
              title: const Text('取り込みメモ'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (displayPost.imagePaths.isNotEmpty) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${displayPost.imagePaths.length}枚取得 · '
                              '${selectedImagePaths.length}枚を解析対象に選択',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setDialogState(() {
                              if (selectedImagePaths.length ==
                                  displayPost.imagePaths.length) {
                                selectedImagePaths.clear();
                              } else {
                                selectedImagePaths
                                  ..clear()
                                  ..addAll(displayPost.imagePaths);
                              }
                            }),
                            child: Text(
                              selectedImagePaths.length ==
                                      displayPost.imagePaths.length
                                  ? '選択解除'
                                  : 'すべて選択',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: displayPost.imagePaths.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 1,
                            ),
                        itemBuilder: (context, index) {
                          final path = displayPost.imagePaths[index];
                          final isSelected = selectedImagePaths.contains(path);
                          return Semantics(
                            button: true,
                            selected: isSelected,
                            label: '${index + 1}枚目を解析対象にする',
                            child: InkWell(
                              onTap: () => setDialogState(() {
                                if (!selectedImagePaths.add(path)) {
                                  selectedImagePaths.remove(path);
                                }
                              }),
                              borderRadius: BorderRadius.circular(14),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: PlacePhoto(
                                      path: path,
                                      fallback: const ColoredBox(
                                        color: Color(0xFFE8F1EC),
                                        child: Icon(Icons.image_outlined),
                                      ),
                                    ),
                                  ),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isSelected
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Colors.transparent,
                                        width: 3,
                                      ),
                                      color: isSelected
                                          ? Colors.black.withValues(alpha: .08)
                                          : null,
                                    ),
                                  ),
                                  Positioned(
                                    top: 6,
                                    left: 6,
                                    child: CircleAvatar(
                                      radius: 12,
                                      backgroundColor: Colors.black54,
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    const Positioned(
                                      top: 5,
                                      right: 5,
                                      child: Icon(
                                        Icons.check_circle_rounded,
                                        color: Colors.white,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '選んだ画像だけをまとめて1回のAI解析に使用します。',
                        style: TextStyle(fontSize: 12),
                      ),
                      if (displayPost.imagePaths.length < 10) ...[
                        const SizedBox(height: 4),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final remaining =
                                10 - displayPost.imagePaths.length;
                            final picked = await ImagePicker().pickMultiImage(
                              imageQuality: 92,
                              limit: remaining,
                            );
                            if (picked.isEmpty || !dialogContext.mounted)
                              return;
                            final updated = await controller.addImagesToPost(
                              displayPost,
                              picked.map((image) => image.path).toList(),
                            );
                            if (!dialogContext.mounted) return;
                            setDialogState(() => displayPost = updated);
                          },
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('不足画像をスクショから追加'),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                    SourcePostTile(post: displayPost, compact: true),
                    const SizedBox(height: 16),
                    TextField(
                      controller: memoController,
                      autofocus: false,
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
              actionsOverflowDirection: VerticalDirection.down,
              actions: [
                TextButton(
                  onPressed:
                      displayPost.imagePaths.isNotEmpty &&
                          selectedImagePaths.isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, ''),
                  child: const Text('メモなしで追加'),
                ),
                FilledButton(
                  onPressed:
                      displayPost.imagePaths.isNotEmpty &&
                          selectedImagePaths.isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, memoController.text),
                  child: const Text('追加して検索'),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      _activeShareDialogContext = null;
      disposeAfterFrame([memoController]);
    }
    if (!mounted || memo == null) return;
    await AppScope.read(context).analyzeSharedPost(
      displayPost,
      memo: memo,
      selectedImagePaths: displayPost.imagePaths.isEmpty
          ? null
          : selectedImagePaths.toList(growable: false),
    );
    if (!mounted) return;
    final message = AppScope.read(context).consumeShareToast() ?? '受信箱に保存しました';
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(duration: const Duration(seconds: 2), content: Text(message)),
    );
  }

  bool _requiresImageSelection(SourcePost post) {
    return post.imagePaths.isNotEmpty &&
        (post.service == 'Instagram' || post.service == 'TikTok');
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
            '明日になると自動で再開します。無料の手動追加・場所検索・ピン保存は引き続き利用できます。ホームの「手動で追加」から続けられます。',
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
            children: const [MapsTab(), InboxTab(), PlansTab(), ProfileTab()],
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
