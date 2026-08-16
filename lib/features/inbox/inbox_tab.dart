import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/source_link_service.dart';
import '../../services/post_category_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/place_photo.dart';
import '../../widgets/post_category_editor.dart';
import '../extraction/extraction_screen.dart';

class InboxTab extends StatefulWidget {
  const InboxTab({super.key});

  @override
  State<InboxTab> createState() => _InboxTabState();
}

class _InboxTabState extends State<InboxTab> {
  String _query = '';
  String? _selectedArea;
  String? _selectedCategory;
  _InboxView _view = _InboxView.active;
  final Set<String> _selectedPostIds = {};

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final snapshot = controller.hub.snapshot;
    final allPosts = snapshot.sourcePosts.toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    final searchTexts = <String, String>{};
    final areas = <String>{};
    final categories = <String>{};
    final postAreas = <String, Set<String>>{};
    final postCategories = <String, Set<String>>{};
    final savedPostIds = snapshot.placeSources
        .map((source) => source.sourcePostId)
        .toSet();
    final duplicatePostIds = <String>{};
    final seenKeys = <String>{};

    for (final post in allPosts) {
      final candidates = controller.candidatesForPost(post.id);
      final linkedPlaceIds = snapshot.placeSources
          .where((source) => source.sourcePostId == post.id)
          .map((source) => source.placeId)
          .toSet();
      final linkedPlaces = snapshot.places.where(
        (place) => linkedPlaceIds.contains(place.id),
      );
      final values = <String>[
        post.title ?? '',
        post.body ?? '',
        post.userMemo ?? '',
        ...post.userCategories,
        post.url ?? '',
        post.service ?? '',
        for (final candidate in candidates) ...[
          candidate.name,
          candidate.address ?? '',
          candidate.postAddress ?? '',
          candidate.reason ?? '',
          candidate.category ?? '',
          ...candidate.genres,
        ],
        for (final place in linkedPlaces) ...[
          place.name,
          place.address ?? '',
          place.category ?? '',
          place.userMemo ?? '',
          place.saveReason ?? '',
          place.notesFromPost ?? '',
        ],
      ];
      final combined = values.join(' ');
      searchTexts[post.id] = combined.toLowerCase();

      final detectedAreas = _areasFrom(combined);
      postAreas[post.id] = detectedAreas;
      areas.addAll(detectedAreas);

      final detectedCategories = controller.categoriesForPost(post.id).toSet();
      postCategories[post.id] = detectedCategories;
      categories.addAll(detectedCategories);

      final normalizedUrl = (post.url ?? '').trim().toLowerCase().replaceFirst(
        RegExp(r'[?#].*$'),
        '',
      );
      final firstCandidate = candidates.firstOrNull;
      final candidateAddress =
          firstCandidate?.address ?? firstCandidate?.postAddress ?? '';
      final placeKey = firstCandidate == null || candidateAddress.trim().isEmpty
          ? ''
          : '${firstCandidate.name}|$candidateAddress'
                .replaceAll(RegExp(r'\s+'), '')
                .toLowerCase();
      final duplicateKey = normalizedUrl.isNotEmpty
          ? 'url:$normalizedUrl'
          : placeKey.length > 3
          ? 'place:$placeKey'
          : '';
      if (duplicateKey.isNotEmpty && !seenKeys.add(duplicateKey)) {
        duplicatePostIds.add(post.id);
      }
    }

    final normalizedQuery = _query.trim().toLowerCase();
    final posts = allPosts.where((post) {
      final archived = controller.isInboxPostArchived(post.id);
      final job = controller.jobForPost(post.id);
      final needsReview =
          job?.status == AnalysisJobStatus.failed ||
          job?.status == AnalysisJobStatus.cancelled ||
          (job?.status == AnalysisJobStatus.completed &&
              controller.candidatesForPost(post.id).isEmpty);
      final visibleInView = switch (_view) {
        _InboxView.active => !archived,
        _InboxView.unorganized =>
          !archived && !savedPostIds.contains(post.id) && !needsReview,
        _InboxView.saved => !archived && savedPostIds.contains(post.id),
        _InboxView.needsReview => !archived && needsReview,
        _InboxView.archived => archived,
      };
      if (!visibleInView) return false;
      if (normalizedQuery.isNotEmpty &&
          !(searchTexts[post.id] ?? '').contains(normalizedQuery)) {
        return false;
      }
      if (_selectedArea != null &&
          !(postAreas[post.id] ?? const {}).contains(_selectedArea)) {
        return false;
      }
      if (_selectedCategory != null &&
          !(postCategories[post.id] ?? const {}).contains(_selectedCategory)) {
        return false;
      }
      return true;
    }).toList();
    final areaOptions = areas.toList()..sort();
    final categoryOptions = categories.toList()..sort();

    return Column(
      children: [
        PageHeading(
          _selectedPostIds.isEmpty ? '受信箱' : '${_selectedPostIds.length}件を選択中',
          _selectedPostIds.isEmpty
              ? controller.aiBackendConfigured
                    ? '投稿を解析して、追加する場所を選べます。'
                    : '端末内で解析中です。AI解析はまだ設定されていません。'
              : '選択した投稿をまとめて整理できます。',
          action: _selectedPostIds.isEmpty
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _view == _InboxView.archived
                          ? '受信箱に戻す'
                          : 'アーカイブ',
                      onPressed: () => _archiveSelected(
                        context,
                        archived: _view != _InboxView.archived,
                      ),
                      icon: Icon(
                        _view == _InboxView.archived
                            ? Icons.unarchive_outlined
                            : Icons.archive_outlined,
                      ),
                    ),
                    IconButton(
                      tooltip: '削除',
                      onPressed: () => _deleteSelected(context),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                    IconButton(
                      tooltip: '選択を解除',
                      onPressed: () => setState(_selectedPostIds.clear),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
        ),
        if (allPosts.isNotEmpty)
          SizedBox(
            height: 42,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              scrollDirection: Axis.horizontal,
              itemCount: _InboxView.values.length,
              separatorBuilder: (_, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final option = _InboxView.values[index];
                return FilterPill(
                  label: option.label,
                  selected: _view == option,
                  onTap: () => setState(() => _view = option),
                );
              },
            ),
          ),
        if (allPosts.isNotEmpty) const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: QuietSearchField(
            hintText: '店名・住所・投稿内容を検索',
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        if (allPosts.isNotEmpty)
          SizedBox(
            height: 42,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              scrollDirection: Axis.horizontal,
              children: [
                FilterPill(
                  label: 'すべて',
                  selected: _selectedArea == null && _selectedCategory == null,
                  onTap: () => setState(() {
                    _selectedArea = null;
                    _selectedCategory = null;
                  }),
                ),
                const SizedBox(width: 8),
                _InboxFilterMenu(
                  label: _selectedArea ?? '場所',
                  icon: Icons.location_on_outlined,
                  selected: _selectedArea != null,
                  values: areaOptions,
                  onSelected: (value) => setState(() => _selectedArea = value),
                ),
                const SizedBox(width: 8),
                _InboxFilterMenu(
                  label: _selectedCategory ?? 'カテゴリ',
                  icon: Icons.category_outlined,
                  selected: _selectedCategory != null,
                  values: categoryOptions,
                  onSelected: (value) =>
                      setState(() => _selectedCategory = value),
                ),
              ],
            ),
          ),
        if (allPosts.isNotEmpty) const SizedBox(height: 8),
        Expanded(
          child: allPosts.isEmpty
              ? EmptyState(
                  icon: Icons.inbox_rounded,
                  title: 'いまは静か',
                  message: 'Instagram や TikTok から共有すると、\nここに届きます。',
                )
              : posts.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: '見つかりませんでした',
                  message: '検索語や絞り込みを変えてみてください。',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 110),
                  itemCount: posts.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final post = posts[i];
                    final job = controller.jobForPost(post.id);
                    final retryable = controller.isRetryableAnalysis(post.id);
                    final candidates = controller.candidatesForPost(post.id);
                    final namedCandidate = candidates
                        .where(controller.isIdentifiedPlaceCandidate)
                        .firstOrNull;
                    final resolvedTitle = namedCandidate != null
                        ? namedCandidate.name.trim()
                        : post.title == '共有されたURL'
                        ? '${post.service ?? 'SNS'}の投稿'
                        : post.title ?? post.url ?? '無題の投稿';
                    return Dismissible(
                      key: ValueKey(post.id),
                      direction: _selectedPostIds.isEmpty
                          ? DismissDirection.endToStart
                          : DismissDirection.none,
                      confirmDismiss: (_) => _confirmDelete(context, post),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: const Color(0x33C62828),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Icon(Icons.delete_outline_rounded),
                      ),
                      child: _InboxCard(
                        selected: _selectedPostIds.contains(post.id),
                        unread: controller.isInboxPostUnread(post.id),
                        icon: _iconFor(post.service),
                        thumbnailPath: post.displayThumbnailPath,
                        source: post.service ?? 'その他',
                        title: resolvedTitle,
                        memo: post.userMemo,
                        categories:
                            (postCategories[post.id] ?? const <String>{})
                                .toList()
                              ..sort(),
                        status: savedPostIds.contains(post.id)
                            ? '保存済み'
                            : duplicatePostIds.contains(post.id)
                            ? '重複候補'
                            : controller.statusLabelForPost(post),
                        statusColor:
                            savedPostIds.contains(post.id) ||
                                duplicatePostIds.contains(post.id)
                            ? moss
                            : _statusColor(job?.status),
                        onTap: () => _selectedPostIds.isEmpty
                            ? _onTap(context, post, job)
                            : _toggleSelected(post.id),
                        onLongPress: () => _toggleSelected(post.id),
                        actionLabel: retryable
                            ? '再度解析する'
                            : job?.status == AnalysisJobStatus.completed
                            ? '候補を見る'
                            : job?.status == AnalysisJobStatus.processing ||
                                  job?.status == AnalysisJobStatus.pending
                            ? '場所を解析中…'
                            : '詳細を見る',
                        onAction: retryable
                            ? () => _retryAnalysis(context, job)
                            : job?.status == AnalysisJobStatus.completed
                            ? () => _onTap(context, post, job)
                            : null,
                        onMore: () => _showActions(
                          context,
                          post,
                          job,
                          archived: controller.isInboxPostArchived(post.id),
                        ),
                        onFetchImage:
                            post.url != null &&
                                (post.service == 'TikTok' ||
                                    post.service == 'Instagram' ||
                                    post.service == 'YouTube')
                            ? () => _fetchPostImage(context, post)
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Set<String> _areasFrom(String text) {
    final matches = RegExp(r'(北海道|東京都|京都府|大阪府|[一-龥]{2,3}県)').allMatches(text);
    return matches.map((match) => match.group(1)!).toSet();
  }

  void _toggleSelected(String postId) {
    setState(() {
      if (!_selectedPostIds.add(postId)) _selectedPostIds.remove(postId);
    });
  }

  Future<void> _archiveSelected(
    BuildContext context, {
    required bool archived,
  }) async {
    final controller = AppScope.read(context);
    final ids = _selectedPostIds.toList();
    for (final id in ids) {
      await controller.setInboxPostArchived(id, archived: archived);
    }
    if (!context.mounted) return;
    setState(_selectedPostIds.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          archived ? '${ids.length}件をアーカイブしました' : '${ids.length}件を受信箱に戻しました',
        ),
      ),
    );
  }

  Future<void> _deleteSelected(BuildContext context) async {
    final count = _selectedPostIds.length;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$count件を削除しますか？'),
        content: const Text('関連する解析結果も削除されます。保存済みの場所は地図に残ります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (approved != true || !context.mounted) return;
    final controller = AppScope.read(context);
    final ids = _selectedPostIds.toList();
    for (final id in ids) {
      await controller.deleteSourcePost(id);
    }
    if (!context.mounted) return;
    setState(_selectedPostIds.clear);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${ids.length}件を削除しました')));
  }

  Color _statusColor(AnalysisJobStatus? status) {
    return switch (status) {
      AnalysisJobStatus.failed => Colors.red.shade700,
      AnalysisJobStatus.cancelled => Colors.grey.shade600,
      AnalysisJobStatus.processing ||
      AnalysisJobStatus.pending => Colors.orange.shade800,
      _ => moss,
    };
  }

  IconData _iconFor(String? service) {
    return switch (service) {
      'Instagram' => Icons.photo_camera_outlined,
      'TikTok' => Icons.music_note,
      'スクリーンショット' => Icons.image_outlined,
      'テキスト' => Icons.notes_outlined,
      _ => Icons.link,
    };
  }

  Future<void> _onTap(
    BuildContext context,
    SourcePost post,
    AnalysisJob? job,
  ) async {
    await AppScope.read(context).markInboxPostSeen(post.id);
    if (!context.mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (job?.status == AnalysisJobStatus.completed) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExtractionScreen(sourcePostId: post.id),
        ),
      );
      return;
    }
    final controller = AppScope.read(context);
    await _showActions(
      context,
      post,
      job,
      archived: controller.isInboxPostArchived(post.id),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, SourcePost post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('受信箱から削除しますか？'),
        content: Text(
          '「${post.title ?? post.url ?? 'この投稿'}」を削除します。関連する解析結果も消えます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await AppScope.read(context).deleteSourcePost(post.id);
    }
    return ok == true;
  }

  Future<void> _showActions(
    BuildContext context,
    SourcePost post,
    AnalysisJob? job, {
    required bool archived,
  }) async {
    final controller = AppScope.read(context);
    await controller.markInboxPostSeen(post.id);
    if (!context.mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                  child: Text(
                    post.title ?? '投稿の操作',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (controller.categoriesForPost(post.id).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      children: [
                        for (final category in controller.categoriesForPost(
                          post.id,
                        ))
                          Chip(label: Text(category)),
                      ],
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('カテゴリを編集'),
                  subtitle: Text(
                    controller.categoriesForPost(post.id).isEmpty
                        ? 'カテゴリはまだ設定されていません'
                        : controller.categoriesForPost(post.id).join('・'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _editCategories(context, post);
                  },
                ),
                if (post.url != null)
                  ListTile(
                    leading: Icon(_iconFor(post.service)),
                    title: Text(
                      post.url!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      post.service == 'TikTok' ? 'TikTokの元投稿を開く' : '元の投稿を開く',
                    ),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: () => _openSourcePost(ctx, post),
                  ),
                if (job?.status == AnalysisJobStatus.completed)
                  ListTile(
                    leading: const Icon(Icons.checklist),
                    title: const Text('場所を確認して追加'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ExtractionScreen(sourcePostId: post.id),
                        ),
                      );
                    },
                  ),
                if (controller.isRetryableAnalysis(post.id) ||
                    job?.status == AnalysisJobStatus.failed ||
                    job?.status == AnalysisJobStatus.cancelled ||
                    job?.status == AnalysisJobStatus.pending)
                  ListTile(
                    leading: const Icon(Icons.refresh),
                    title: const Text('解析を再試行'),
                    subtitle: job?.errorMessage != null
                        ? Text(
                            job!.errorMessage!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _retryAnalysis(context, job);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: Text(
                    (post.userMemo ?? '').trim().isEmpty ? 'メモを追記' : 'メモを編集',
                  ),
                  subtitle: const Text('店名や住所を追記して、場所をもう一度検索できます'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _editAndRetry(context, post, job);
                  },
                ),
                if (job?.status == AnalysisJobStatus.processing ||
                    job?.status == AnalysisJobStatus.pending)
                  ListTile(
                    leading: const Icon(Icons.cancel_outlined),
                    title: const Text('解析をキャンセル'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (job != null) {
                        await AppScope.read(context).analysis.cancel(job.id);
                      }
                    },
                  ),
                ListTile(
                  leading: Icon(
                    archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                  title: Text(archived ? '受信箱に戻す' : 'アーカイブする'),
                  subtitle: Text(archived ? '通常の受信箱に再表示します' : '削除せずに受信箱を整理します'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await AppScope.read(
                      context,
                    ).setInboxPostArchived(post.id, archived: !archived);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('削除', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _confirmDelete(context, post);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSourcePost(BuildContext context, SourcePost post) async {
    var opened = false;
    try {
      opened = await SourceLinkService().openPost(post);
    } catch (_) {
      opened = false;
    }
    if (!context.mounted || opened) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('元の投稿を開けませんでした')));
  }

  Future<void> _editAndRetry(
    BuildContext context,
    SourcePost post,
    AnalysisJob? job,
  ) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!context.mounted) return;
    final textController = TextEditingController(text: post.userMemo ?? '');
    try {
      final body = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('投稿文を補足'),
          content: SingleChildScrollView(
            child: TextField(
              controller: textController,
              minLines: 4,
              maxLines: 8,
              autofocus: false,
              decoration: const InputDecoration(
                hintText: '例：店名、東京都渋谷区…',
                helperText: '元のURLと画像はそのまま残ります',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, textController.text.trim()),
              child: const Text('再解析'),
            ),
          ],
        ),
      );
      if (body == null || !context.mounted) return;
      final controller = AppScope.read(context);
      final categories = <String>{
        ...controller.categoriesForPost(post.id),
        ...suggestPostCategories(body),
      }.toList()..sort();
      await controller.sourcePosts.update(
        post.copyWith(
          userMemo: body,
          clearUserMemo: body.isEmpty,
          userCategories: categories,
          userCategoriesSet: post.userCategoriesSet || categories.isNotEmpty,
          updatedAt: DateTime.now(),
        ),
      );
      if (job != null) {
        await controller.analysis.retry(job.id);
        await controller.analysisRunner.runJob(job.id);
      }
    } finally {
      textController.dispose();
    }
  }

  Future<void> _retryAnalysis(BuildContext context, AnalysisJob? job) async {
    if (job == null) return;
    final controller = AppScope.read(context);
    await controller.analysis.retry(job.id);
    await controller.analysisRunner.runJob(job.id);
    if (!context.mounted) return;
    final retryable = controller.isRetryableAnalysis(job.sourcePostId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(retryable ? '解析を完了できませんでした。通信状態を確認してください' : '再解析が完了しました'),
      ),
    );
  }

  Future<void> _editCategories(BuildContext context, SourcePost post) async {
    final result = await showPostCategoryEditor(
      context,
      initialCategories: AppScope.read(context).categoriesForPost(post.id),
    );
    if (result == null || !context.mounted) return;
    await AppScope.read(context).sourcePosts.update(
      post.copyWith(
        userCategories: result,
        userCategoriesSet: true,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _fetchPostImage(BuildContext context, SourcePost post) async {
    final controller = AppScope.read(context);
    final succeeded = await controller.refreshPostImage(post);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          succeeded ? '投稿画像を取得しました' : '投稿画像を取得できませんでした。もう一度お試しください',
        ),
      ),
    );
  }
}

enum _InboxView {
  active('受信箱'),
  unorganized('未整理'),
  saved('保存済み'),
  needsReview('要確認'),
  archived('アーカイブ');

  const _InboxView(this.label);
  final String label;
}

class _InboxFilterMenu extends StatelessWidget {
  const _InboxFilterMenu({
    required this.label,
    required this.icon,
    required this.selected,
    required this.values,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final List<String> values;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      enabled: values.isNotEmpty,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final value in values)
          PopupMenuItem<String>(value: value, child: Text(value)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? mossDeep : Colors.white.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: selected ? Colors.white : mossDeep),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : mossDeep,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.expand_more_rounded,
              size: 17,
              color: selected ? Colors.white : mossDeep,
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({
    required this.selected,
    required this.unread,
    required this.icon,
    this.thumbnailPath,
    required this.source,
    required this.title,
    this.memo,
    this.categories = const [],
    required this.status,
    required this.statusColor,
    this.onTap,
    this.onLongPress,
    this.actionLabel,
    this.onAction,
    this.onMore,
    this.onFetchImage,
  });

  final bool selected;
  final bool unread;
  final IconData icon;
  final String? thumbnailPath;
  final String source;
  final String title;
  final String? memo;
  final List<String> categories;
  final String status;
  final Color statusColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onMore;
  final VoidCallback? onFetchImage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: unread
          ? colors.primaryContainer.withValues(alpha: .38)
          : selected
          ? colors.secondaryContainer.withValues(alpha: .55)
          : Colors.white.withValues(alpha: 0.52),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: unread
              ? colors.primary.withValues(alpha: .28)
              : selected
              ? colors.secondary.withValues(alpha: .7)
              : colors.outlineVariant.withValues(alpha: .25),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 6, 13),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: mint.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: thumbnailPath == null
                          ? Icon(icon, color: mossDeep)
                          : PlacePhoto(
                              path: thumbnailPath!,
                              fit: BoxFit.cover,
                              fallback: Icon(icon, color: mossDeep),
                            ),
                    ),
                  ),
                  if (unread)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.surface, width: 2),
                        ),
                      ),
                    ),
                  if (selected)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: .86),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          color: colors.onPrimary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (memo?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 5),
                      Text(
                        'メモ：${memo!.trim()}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF596A61),
                        ),
                      ),
                    ],
                    if (categories.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final category in categories.take(3))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: mintSoft,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                category,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (onFetchImage != null) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: onFetchImage,
                          icon: const Icon(
                            Icons.image_search_rounded,
                            size: 18,
                          ),
                          label: Text(
                            thumbnailPath == null ? '投稿画像を取得' : '投稿画像を再取得',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (unread) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '未読',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colors.onPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 7),
                        ],
                        Flexible(
                          child: Text(
                            source,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: .11),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (actionLabel != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          onPressed: onAction,
                          icon: Icon(
                            onAction == null
                                ? Icons.hourglass_top_rounded
                                : Icons.add_location_alt_outlined,
                            size: 18,
                          ),
                          label: Text(actionLabel!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: onMore,
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
