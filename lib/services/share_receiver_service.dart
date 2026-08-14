import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/errors.dart';
import '../models/models.dart';
import '../repositories/local_repositories.dart';
import '../repositories/repository_interfaces.dart';
import 'location_services.dart';
import 'platform_share_bridge.dart';

class SharedContent {
  const SharedContent({
    this.url,
    this.text,
    this.imagePaths = const [],
    this.service,
    this.title,
  });

  final String? url;
  final String? text;
  final List<String> imagePaths;
  final String? service;
  final String? title;

  bool get isEmpty =>
      (url == null || url!.trim().isEmpty) &&
      (text == null || text!.trim().isEmpty) &&
      imagePaths.isEmpty &&
      (title == null || title!.trim().isEmpty);

  Map<String, dynamic> toMap() => {
    'url': url,
    'text': text,
    'imagePaths': imagePaths,
    'service': service,
    'title': title,
  };

  /// ネイティブ／JSON／プレーンテキストからの安全なパース。
  static SharedContent? tryParse(dynamic raw) {
    if (raw == null) return null;

    if (raw is SharedContent) return raw;

    if (raw is String && raw.trim().isNotEmpty) {
      final trimmed = raw.trim();
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return tryParse(decoded);
        }
      } catch (_) {}
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        return SharedContent(url: trimmed);
      }
      return SharedContent(text: trimmed, title: '共有されたテキスト');
    }

    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);

    final imagePaths = <String>[];
    final images = map['imagePaths'] ?? map['paths'] ?? map['mediaPaths'];
    if (images is List) {
      for (final item in images) {
        if (item == null) continue;
        final value = item.toString().trim();
        if (value.isNotEmpty) imagePaths.add(value);
      }
    }
    final singlePath = map['path'] ?? map['imagePath'];
    if (singlePath != null) {
      final value = singlePath.toString().trim();
      if (value.isNotEmpty) imagePaths.add(value);
    }

    var url = map['url']?.toString();
    var text = map['text']?.toString() ?? map['content']?.toString();
    if ((url == null || url.isEmpty) && text != null) {
      final trimmed = text.trim();
      final firstToken = trimmed.split(RegExp(r'\s+')).first;
      if (firstToken.startsWith('http://') ||
          firstToken.startsWith('https://')) {
        url = firstToken;
        if (trimmed == firstToken) {
          text = null;
        }
      }
    }

    final content = SharedContent(
      url: (url == null || url.isEmpty) ? null : url,
      text: (text == null || text.isEmpty) ? null : text,
      imagePaths: imagePaths,
      service: map['service']?.toString(),
      title: map['title']?.toString(),
    );
    return content.isEmpty ? null : content;
  }
}

/// SNS共有の受信。まず受信箱へ保存し、解析ジョブを積む。
abstract class ShareReceiverService {
  /// 受信箱へ即保存して返す。解析はデフォルトでバックグラウンド。
  Future<SourcePost> receive(
    SharedContent content, {
    bool waitForAnalysis = false,
    bool analyze = true,
  });

  Future<SourcePost> refreshOfficialPreview(
    SourcePost post, {
    bool force = false,
  });
}

class LocalShareReceiverService implements ShareReceiverService {
  LocalShareReceiverService({
    required this.sourcePosts,
    required this.analysis,
    required this.analysisService,
    this.autoAnalyze = true,
    this.officialPreviewLoader,
  });

  final SourcePostRepository sourcePosts;
  final AnalysisRepository analysis;
  final PostAnalysisService analysisService;
  final bool autoAnalyze;
  final Future<String?> Function(String sharedUrl)? officialPreviewLoader;

  bool _busy = false;

  /// 既存投稿の代表画像を、対応SNSの公式oEmbedから再取得する。
  @override
  Future<SourcePost> refreshOfficialPreview(
    SourcePost post, {
    bool force = false,
  }) async {
    if ((!force && post.imagePaths.isNotEmpty) || post.url == null) return post;
    final preview = await _loadOfficialPreview(post.url!);
    if (preview == null) {
      throw StateError('この投稿から利用できる画像を取得できませんでした');
    }
    return sourcePosts.update(
      post.copyWith(imagePaths: [preview], updatedAt: DateTime.now()),
    );
  }

  @override
  Future<SourcePost> receive(
    SharedContent content, {
    bool waitForAnalysis = false,
    bool analyze = true,
  }) async {
    if (_busy) {
      throw StateError('共有の取り込み処理中です。完了してから再試行してください。');
    }
    _busy = true;
    try {
      final service =
          content.service ?? _guessService(content.url, content.text);
      final firstLine = content.text
          ?.split('\n')
          .map((e) => e.trim())
          .firstWhere((e) => e.isNotEmpty, orElse: () => '');
      final title =
          content.title ??
          ((firstLine != null && firstLine.isNotEmpty) ? firstLine : null) ??
          content.url ??
          (content.imagePaths.isNotEmpty ? '共有された画像' : null) ??
          '共有された投稿';

      var post = await sourcePosts.create(
        SourcePost(
          url: content.url,
          service: service,
          title: title,
          body: content.text,
          imagePaths: content.imagePaths,
        ),
      );
      final job = await analysis.enqueue(post.id);

      if (autoAnalyze && analyze) {
        Future<void> analyzePreparedPost() async {
          if (post.imagePaths.isEmpty && post.url != null) {
            post = await _attachOfficialPreview(post);
          }
          await _analyze(job, post);
        }

        if (waitForAnalysis) {
          await analyzePreparedPost();
        } else {
          unawaited(analyzePreparedPost());
        }
      } else if (post.imagePaths.isEmpty && post.url != null) {
        unawaited(_attachOfficialPreview(post));
      }
      return post;
    } finally {
      _busy = false;
    }
  }

  Future<SourcePost> _attachOfficialPreview(SourcePost post) async {
    try {
      final preview = await _loadOfficialPreview(post.url!);
      if (preview == null) return post;
      return await sourcePosts.update(
        post.copyWith(imagePaths: [preview], updatedAt: DateTime.now()),
      );
    } catch (_) {
      // 画像は補助情報。失敗しても投稿保存と場所解析は継続する。
      return post;
    }
  }

  Future<String?> _loadOfficialPreview(String sharedUrl) =>
      officialPreviewLoader?.call(sharedUrl) ?? _officialPreviewFor(sharedUrl);

  Future<String?> _officialPreviewFor(String sharedUrl) async {
    final source = Uri.tryParse(sharedUrl);
    if (source == null || source.scheme != 'https') return null;
    final host = source.host.toLowerCase();
    late final Uri endpoint;
    late final List<String> allowedImageDomains;
    if (_matchesHost(host, 'tiktok.com')) {
      endpoint = Uri.https('www.tiktok.com', '/oembed', {'url': sharedUrl});
      allowedImageDomains = const [
        'tiktokcdn.com',
        'tiktokcdn-us.com',
        'muscdn.com',
      ];
    } else if (_matchesHost(host, 'youtube.com') || host == 'youtu.be') {
      endpoint = Uri.https('www.youtube.com', '/oembed', {
        'url': sharedUrl,
        'format': 'json',
      });
      allowedImageDomains = const ['ytimg.com'];
    } else {
      return null;
    }

    final response = await http
        .get(endpoint, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 7));
    if (response.statusCode != 200 || response.body.length > 256 * 1024) {
      return null;
    }
    final json = jsonDecode(response.body);
    if (json is! Map) return null;
    final raw = json['thumbnail_url']?.toString();
    final image = raw == null ? null : Uri.tryParse(raw);
    if (image == null || image.scheme != 'https') return null;
    final imageHost = image.host.toLowerCase();
    if (!allowedImageDomains.any((domain) => _matchesHost(imageHost, domain))) {
      return null;
    }
    return image.toString();
  }

  static bool _matchesHost(String host, String domain) =>
      host == domain || host.endsWith('.$domain');

  Future<void> _analyze(AnalysisJob job, SourcePost post) async {
    try {
      await analysis.update(job.copyWith(status: AnalysisJobStatus.processing));
      final result = await analysisService.analyze(
        PostAnalysisRequest(
          sourcePostId: post.id,
          url: post.url,
          text: _analysisText(post),
          imageUrls: post.imagePaths,
        ),
      );
      final mergedImages = _mergedAnalysisImages(post, result);
      if (!_samePaths(post.imagePaths, mergedImages)) {
        post = await sourcePosts.update(
          post.copyWith(imagePaths: mergedImages, updatedAt: DateTime.now()),
        );
      }
      if (!post.userCategoriesSet) {
        final categories = _analysisCategories(result);
        if (categories.isNotEmpty) {
          post = await sourcePosts.update(
            post.copyWith(
              userCategories: categories,
              userCategoriesSet: true,
              updatedAt: DateTime.now(),
            ),
          );
        }
      }
      await analysis.update(
        job.copyWith(
          status: AnalysisJobStatus.completed,
          resultJson: jsonEncode({
            'candidates': result.candidates.map((c) => c.toJson()).toList(),
            'raw_summary': result.rawSummary,
            'analysis_source': result.analysisSource,
          }),
        ),
      );
    } catch (e) {
      await analysis.update(
        job.copyWith(
          status: AnalysisJobStatus.failed,
          errorMessage: toUserMessage(e),
        ),
      );
    }
  }

  String _guessService(String? url, String? text) {
    final hay = '${url ?? ''} ${text ?? ''}'.toLowerCase();
    if (hay.contains('instagram.com')) return 'Instagram';
    if (hay.contains('tiktok.com')) return 'TikTok';
    if (hay.contains('youtube.com') || hay.contains('youtu.be')) {
      return 'YouTube';
    }
    if (url != null && url.isNotEmpty) return 'URL';
    return 'その他';
  }
}

/// 解析ジョブの再試行ヘルパー。
class AnalysisRunner {
  AnalysisRunner({required this.hub, required this.analysisService});

  final LocalRepositoryHub hub;
  final PostAnalysisService analysisService;

  Future<void> runJob(String jobId) async {
    final jobs = await hub.analysis.getAll();
    final job = jobs.cast<AnalysisJob?>().firstWhere(
      (j) => j!.id == jobId,
      orElse: () => null,
    );
    if (job == null) return;
    final storedPost = await hub.sourcePosts.getById(job.sourcePostId);
    if (storedPost == null) return;
    var post = storedPost;

    await hub.analysis.update(
      job.copyWith(status: AnalysisJobStatus.processing, errorMessage: null),
    );
    try {
      final result = await analysisService.analyze(
        PostAnalysisRequest(
          sourcePostId: post.id,
          url: post.url,
          text: _analysisText(post),
          imageUrls: post.imagePaths,
        ),
      );
      final mergedImages = _mergedAnalysisImages(post, result);
      if (!_samePaths(post.imagePaths, mergedImages)) {
        post = await hub.sourcePosts.update(
          post.copyWith(imagePaths: mergedImages, updatedAt: DateTime.now()),
        );
      }
      if (!post.userCategoriesSet) {
        final categories = _analysisCategories(result);
        if (categories.isNotEmpty) {
          post = await hub.sourcePosts.update(
            post.copyWith(
              userCategories: categories,
              userCategoriesSet: true,
              updatedAt: DateTime.now(),
            ),
          );
        }
      }
      await hub.analysis.update(
        job.copyWith(
          status: AnalysisJobStatus.completed,
          resultJson: jsonEncode({
            'candidates': result.candidates.map((c) => c.toJson()).toList(),
            'raw_summary': result.rawSummary,
            'analysis_source': result.analysisSource,
          }),
        ),
      );
    } catch (e) {
      await hub.analysis.update(
        job.copyWith(
          status: AnalysisJobStatus.failed,
          errorMessage: toUserMessage(e),
        ),
      );
    }
  }
}

List<String> _analysisCategories(PostAnalysisResponse result) {
  final values = <String>{};
  for (final candidate in result.candidates) {
    final category = candidate.category?.trim();
    if (category != null && category.isNotEmpty && category != 'その他') {
      values.add(category);
    }
    values.addAll(
      candidate.genres
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty && value != 'その他'),
    );
  }
  return values.toList()..sort();
}

List<String> _mergedAnalysisImages(
  SourcePost post,
  PostAnalysisResponse result,
) {
  final fetched = result.previewImagePaths.isNotEmpty
      ? result.previewImagePaths
      : [if (result.previewImagePath != null) result.previewImagePath!];
  if (fetched.isEmpty) return post.imagePaths;
  return {...post.imagePaths, ...fetched}.take(5).toList(growable: false);
}

bool _samePaths(List<String> left, List<String> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String? _analysisText(SourcePost post) {
  final title = post.title?.trim();
  final usefulTitle =
      title == null ||
          title.isEmpty ||
          title == '共有された投稿' ||
          title == '共有された画像' ||
          title.startsWith('http://') ||
          title.startsWith('https://')
      ? null
      : title;
  final seen = <String>{};
  final parts = [usefulTitle, post.body?.trim(), post.userMemo?.trim()]
      .whereType<String>()
      .where((value) => value.isNotEmpty && seen.add(value))
      .toList();
  return parts.isEmpty ? null : parts.join('\n');
}

/// OS共有 → 受信箱保存 → UI通知 をまとめるコーディネータ。
class ShareIntakeCoordinator {
  ShareIntakeCoordinator({
    required this.shareReceiver,
    PlatformShareBridge? bridge,
  }) : bridge = bridge ?? PlatformShareBridge();

  final ShareReceiverService shareReceiver;
  final PlatformShareBridge bridge;

  final _savedController = StreamController<SourcePost>.broadcast();
  Stream<SourcePost> get onSaved => _savedController.stream;

  String? lastSavedMessage;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    bridge.onShared = _handleShared;
    await bridge.attach();
  }

  Future<void> dispose() async {
    await bridge.detach();
    await _savedController.close();
  }

  Future<SourcePost?> _handleShared(SharedContent content) async {
    try {
      // OS共有では、ユーザーが補足メモを入力してから解析を開始する。
      final post = await shareReceiver.receive(content, analyze: false);
      lastSavedMessage = '受信箱に保存しました';
      if (!_savedController.isClosed) {
        _savedController.add(post);
      }
      return post;
    } catch (_) {
      lastSavedMessage = '共有の保存に失敗しました。投稿内容は再共有してください。';
      return null;
    }
  }

  /// テストやUIからの手動投入用。
  Future<SourcePost> ingest(SharedContent content) async {
    final post = await shareReceiver.receive(content);
    lastSavedMessage = '受信箱に保存しました';
    if (!_savedController.isClosed) {
      _savedController.add(post);
    }
    return post;
  }
}
