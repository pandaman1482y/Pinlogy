import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/errors.dart';
import '../models/models.dart';
import '../repositories/local_data_store.dart';
import '../repositories/local_repositories.dart';
import '../repositories/repository_interfaces.dart';
import '../services/device_location_service.dart';
import '../services/ai_post_analysis_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/directions_service.dart';
import '../services/free_place_search_service.dart';
import '../services/in_app_route_service.dart';
import '../services/local_post_analysis_service.dart';
import '../services/location_services.dart';
import '../services/post_category_service.dart';
import '../services/share_receiver_service.dart';
import '../services/source_link_service.dart';
import '../services/source_media_store.dart';

/// UIから参照するアプリ状態。
class PinlogyController extends ChangeNotifier {
  PinlogyController({
    LocalDataStore? store,
    PostAnalysisService? analysisService,
    GeocodingService? geocodingService,
    PlaceSearchService? placeSearchService,
    DirectionsService? directionsService,
    DeviceLocationService? deviceLocationService,
    InAppRouteService? inAppRouteService,
    CloudSyncService? cloudSyncService,
    bool seedIfEmpty = true,
    this.enablePlatformShare = true,
  }) : hub = LocalRepositoryHub(store ?? SharedPreferencesStore()),
       analysisService =
           analysisService ??
           AiPostAnalysisService(fallback: LocalPostAnalysisService()),
       geocoding = geocodingService ?? GsiGeocodingService(),
       placeSearch = placeSearchService ?? FreePlaceSearchService(),
       directions = directionsService ?? DirectionsService(),
       deviceLocation = deviceLocationService ?? GeolocatorLocationService(),
       inAppRoutes = inAppRouteService ?? InAppRouteService(),
       cloud = cloudSyncService ?? CloudSyncService(),
       sourceLinks = SourceLinkService(),
       sourceMedia = SourceMediaStore(),
       _seedIfEmpty = seedIfEmpty;

  final LocalRepositoryHub hub;
  final PostAnalysisService analysisService;
  final GeocodingService geocoding;
  final PlaceSearchService placeSearch;
  final DirectionsService directions;
  final DeviceLocationService deviceLocation;
  final InAppRouteService inAppRoutes;
  final CloudSyncService cloud;
  final SourceLinkService sourceLinks;
  final SourceMediaStore sourceMedia;
  final bool _seedIfEmpty;

  bool get aiBackendConfigured => AiPostAnalysisService.backendConfigured;

  /// false にすると MethodChannel を触らない（テスト用）。
  final bool enablePlatformShare;

  late final ShareReceiverService shareReceiver = LocalShareReceiverService(
    sourcePosts: hub.sourcePosts,
    analysis: hub.analysis,
    analysisService: analysisService,
    mediaStore: sourceMedia,
  );
  late final AnalysisRunner analysisRunner = AnalysisRunner(
    hub: hub,
    analysisService: analysisService,
  );
  late final ShareIntakeCoordinator shareIntake = ShareIntakeCoordinator(
    shareReceiver: shareReceiver,
  );

  bool loading = true;
  String? loadError;
  bool busy = false;
  final Set<String> _seenInboxPostIds = {};
  final Set<String> _archivedInboxPostIds = {};
  static const _seenInboxPostIdsKey = 'pinlogy_seen_inbox_post_ids_v1';
  static const _archivedInboxPostIdsKey = 'pinlogy_archived_inbox_post_ids_v1';
  static const _legacyInboxSeenKey = 'pinlogy_inbox_seen_at_v1';
  static const _aiQuotaNoticeDateKey = 'pinlogy_ai_quota_notice_date_v1';

  /// 共有保存直後の短い案内。HomeScreen が表示したら消費する。
  String? pendingShareToast;
  final Queue<SourcePost> _pendingSharedPosts = Queue<SourcePost>();

  MapRepository get maps => hub.maps;
  PlaceRepository get places => hub.places;
  SourcePostRepository get sourcePosts => hub.sourcePosts;
  AnalysisRepository get analysis => hub.analysis;
  VisitRepository get visits => hub.visits;
  TagRepository get tags => hub.tags;
  PlanRepository get plans => hub.plans;

  Future<void> initialize() async {
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      hub.addListener(notifyListeners);
      final preferences = await SharedPreferences.getInstance();
      _seenInboxPostIds.addAll(
        preferences.getStringList(_seenInboxPostIdsKey) ?? const [],
      );
      _archivedInboxPostIds.addAll(
        preferences.getStringList(_archivedInboxPostIdsKey) ?? const [],
      );
      await hub.load(seedIfEmpty: _seedIfEmpty);
      final legacySeenAt = preferences.getInt(_legacyInboxSeenKey) ?? 0;
      if (_seenInboxPostIds.isEmpty && legacySeenAt > 0) {
        _seenInboxPostIds.addAll(
          hub.snapshot.sourcePosts
              .where(
                (post) =>
                    post.receivedAt.millisecondsSinceEpoch <= legacySeenAt,
              )
              .map((post) => post.id),
        );
        await preferences.setStringList(
          _seenInboxPostIdsKey,
          _seenInboxPostIds.toList(),
        );
      }
      shareIntake.onSaved.listen((post) {
        _pendingSharedPosts.addLast(post);
        pendingShareToast = shareIntake.lastSavedMessage ?? '受信箱に保存しました';
        notifyListeners();
      });
      // ネイティブ共有の待ちで起動をブロックしない
      if (enablePlatformShare) {
        unawaited(shareIntake.start());
        unawaited(_repairMissingThumbnails(preferences));
      }
    } catch (error) {
      loadError = toUserMessage(error);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _repairMissingThumbnails(SharedPreferences preferences) async {
    const attemptsKey = 'pinlogy_thumbnail_repair_attempts_v1';
    final attempted =
        preferences.getStringList(attemptsKey)?.toSet() ?? <String>{};
    var attemptedThisLaunch = 0;
    for (final post in hub.snapshot.sourcePosts) {
      if (attemptedThisLaunch >= 3) break;
      final thumbnail = post.displayThumbnailPath;
      if (await sourceMedia.isAvailable(thumbnail)) {
        attempted.remove(post.id);
        continue;
      }
      if (attempted.contains(post.id) ||
          !AiPostAnalysisService.supportsRemotePreviewUrl(post.url)) {
        continue;
      }
      attempted.add(post.id);
      attemptedThisLaunch++;
      // preview_onlyのためAI利用回数・AI料金は消費しない。
      await refreshPostImage(post);
    }
    await preferences.setStringList(attemptsKey, attempted.toList());
  }

  Future<void> deleteSourcePost(String sourcePostId) async {
    final post = await sourcePosts.getById(sourcePostId);
    await sourcePosts.delete(sourcePostId);
    if (post == null) return;
    final protectedPaths = hub.snapshot.places
        .map((place) => place.coverImagePath)
        .whereType<String>()
        .toSet();
    await sourceMedia.deleteForPost(
      sourcePostId,
      protectedPaths: protectedPaths,
    );
  }

  String? consumeShareToast() {
    final message = pendingShareToast;
    pendingShareToast = null;
    return message;
  }

  SourcePost? consumePendingSharedPost() {
    return _pendingSharedPosts.isEmpty
        ? null
        : _pendingSharedPosts.removeFirst();
  }

  List<SourcePost> consumePendingSharedPosts() {
    final posts = _pendingSharedPosts.toList(growable: false);
    _pendingSharedPosts.clear();
    return posts;
  }

  void acknowledgeSharedPost(String sourcePostId) {
    _pendingSharedPosts.removeWhere((post) => post.id == sourcePostId);
  }

  Future<void> analyzeSharedPost(SourcePost post, {String? memo}) async {
    var currentPost = await sourcePosts.getById(post.id) ?? post;
    if (currentPost.imagePaths.isEmpty && currentPost.url != null) {
      try {
        currentPost = await shareReceiver.refreshOfficialPreview(currentPost);
      } catch (_) {
        // 画像取得に失敗しても投稿文・URL・メモで解析を続ける。
      }
    }
    final trimmedMemo = memo?.trim() ?? '';
    if (trimmedMemo.isNotEmpty) {
      final categories = <String>{
        ...categoriesForPost(post.id),
        ...suggestPostCategories(trimmedMemo),
      }.toList()..sort();
      await sourcePosts.update(
        currentPost.copyWith(
          userMemo: trimmedMemo,
          userCategories: categories,
          userCategoriesSet:
              currentPost.userCategoriesSet || categories.isNotEmpty,
          updatedAt: DateTime.now(),
        ),
      );
    }
    final job = await analysis.getBySourcePostId(post.id);
    if (job != null) {
      await analysisRunner.runJob(job.id);
    }
  }

  Future<bool> consumeAiQuotaNotice() async {
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final reachedToday = hub.snapshot.analysisJobs.any((job) {
      final updated = job.updatedAt.toLocal();
      if (updated.year != now.year ||
          updated.month != now.month ||
          updated.day != now.day) {
        return false;
      }
      final raw = job.resultJson;
      if (raw == null || raw.isEmpty) return false;
      try {
        final value = jsonDecode(raw) as Map<String, dynamic>;
        return value['analysis_source'] == 'quota_fallback';
      } catch (_) {
        return false;
      }
    });
    if (!reachedToday) return false;
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getString(_aiQuotaNoticeDateKey) == today) return false;
    await preferences.setString(_aiQuotaNoticeDateKey, today);
    return true;
  }

  @override
  void dispose() {
    hub.removeListener(notifyListeners);
    unawaited(shareIntake.dispose());
    super.dispose();
  }

  Future<T?> runExclusive<T>(Future<T> Function() action) async {
    if (busy) {
      throw StateError('ほかの処理の完了を待ってからもう一度お試しください');
    }
    busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  int get inboxBadgeCount {
    return hub.snapshot.sourcePosts
        .where(
          (post) =>
              !_archivedInboxPostIds.contains(post.id) &&
              !_seenInboxPostIds.contains(post.id),
        )
        .length;
  }

  bool isInboxPostUnread(String sourcePostId) {
    return !_seenInboxPostIds.contains(sourcePostId);
  }

  bool isInboxPostArchived(String sourcePostId) {
    return _archivedInboxPostIds.contains(sourcePostId);
  }

  Future<void> setInboxPostArchived(
    String sourcePostId, {
    required bool archived,
  }) async {
    final changed = archived
        ? _archivedInboxPostIds.add(sourcePostId)
        : _archivedInboxPostIds.remove(sourcePostId);
    if (!changed) return;
    if (archived) _seenInboxPostIds.add(sourcePostId);
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _archivedInboxPostIdsKey,
      _archivedInboxPostIds.toList(),
    );
    if (archived) {
      await preferences.setStringList(
        _seenInboxPostIdsKey,
        _seenInboxPostIds.toList(),
      );
    }
  }

  Future<void> markInboxPostSeen(String sourcePostId) async {
    if (!_seenInboxPostIds.add(sourcePostId)) return;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setStringList(
      _seenInboxPostIdsKey,
      _seenInboxPostIds.toList(),
    );
  }

  AnalysisJob? jobForPost(String sourcePostId) {
    try {
      return hub.snapshot.analysisJobs.firstWhere(
        (j) => j.sourcePostId == sourcePostId,
      );
    } catch (_) {
      return null;
    }
  }

  List<ExtractionCandidate> candidatesForPost(String sourcePostId) {
    final job = jobForPost(sourcePostId);
    if (job?.resultJson == null) return const [];
    try {
      final map = jsonDecode(job!.resultJson!) as Map<String, dynamic>;
      final list = (map['candidates'] as List? ?? const []);
      return list
          .map((e) => ExtractionCandidate.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<SourcePost> sourcesForPlace(String placeId) {
    final ids = hub.snapshot.placeSources
        .where((ps) => ps.placeId == placeId)
        .map((ps) => ps.sourcePostId)
        .toSet();
    return hub.snapshot.sourcePosts.where((p) => ids.contains(p.id)).toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
  }

  SourcePost? primarySourceForPlace(String placeId) {
    final sources = sourcesForPlace(placeId);
    // URL付きを優先
    for (final post in sources) {
      if (sourceLinks.canOpen(post)) return post;
    }
    return sources.isEmpty ? null : sources.first;
  }

  String statusLabelForPost(SourcePost post) {
    final job = jobForPost(post.id);
    if (job == null) return '未解析';
    if (job.status == AnalysisJobStatus.completed) {
      final candidates = candidatesForPost(post.id);
      final count = candidates.where(isIdentifiedPlaceCandidate).length;
      if (count > 0) return '$count件の場所を検出';
      return candidates.isEmpty ? '場所は見つかりませんでした' : '場所候補を確認してください';
    }
    if (job.status == AnalysisJobStatus.failed) {
      return job.errorMessage ?? '解析に失敗';
    }
    return job.status.label;
  }

  String? analysisSourceForPost(String sourcePostId) {
    final raw = jobForPost(sourcePostId)?.resultJson;
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      return value['analysis_source']?.toString();
    } catch (_) {
      return null;
    }
  }

  bool isRetryableAnalysis(String sourcePostId) {
    return const {
      'auth_fallback',
      'function_missing_fallback',
      'server_fallback',
      'invalid_response_fallback',
      'timeout_fallback',
      'network_fallback',
      'local_fallback',
      'instagram_media_unavailable',
    }.contains(analysisSourceForPost(sourcePostId));
  }

  List<String> categoriesForPost(String sourcePostId) {
    final post = hub.snapshot.sourcePosts
        .where((item) => item.id == sourcePostId)
        .firstOrNull;
    if (post?.userCategoriesSet == true) {
      return post!.userCategories.toList()..sort();
    }
    final values = <String>{};
    for (final candidate in candidatesForPost(sourcePostId)) {
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

  Future<bool> refreshPostImage(SourcePost post) async {
    try {
      if (AiPostAnalysisService.supportsRemotePreviewUrl(post.url) &&
          analysisService is AiPostAnalysisService) {
        final paths = await (analysisService as AiPostAnalysisService)
            .fetchSocialPostPreviews(
              PostAnalysisRequest(sourcePostId: post.id, url: post.url),
            );
        if (paths.isNotEmpty) {
          final retained = <String>[];
          for (final path in post.imagePaths) {
            if (await sourceMedia.isAvailable(path)) retained.add(path);
          }
          final merged = {
            ...retained,
            ...paths,
          }.take(SourceMediaStore.maxImages).toList(growable: false);
          await sourcePosts.update(
            post.copyWith(
              imagePaths: merged,
              thumbnailPath: paths.first,
              updatedAt: DateTime.now(),
            ),
          );
          return true;
        }
      }
      await shareReceiver.refreshOfficialPreview(post, force: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool isIdentifiedPlaceCandidate(ExtractionCandidate candidate) {
    final name = candidate.name.trim();
    final meaningfulName =
        name.isNotEmpty && name != '共有された場所' && name != '名称を確認してください';
    final hasLocation =
        candidate.address?.trim().isNotEmpty == true ||
        (candidate.latitude != null && candidate.longitude != null);
    return meaningfulName &&
        candidate.match != PlaceMatchConfidence.unresolved &&
        (hasLocation || (candidate.confidencePercent ?? 0) >= 60);
  }

  Future<List<Place>> addCandidatesToMap({
    required List<ExtractionCandidate> candidates,
    required String mapId,
    required String sourcePostId,
    bool resolveAddresses = false,
  }) async {
    return await runExclusive(() async {
          final created = <Place>[];
          for (final c in candidates) {
            GeoResult? geo;
            if (resolveAddresses &&
                c.latitude == null &&
                c.longitude == null &&
                c.address?.isNotEmpty == true) {
              geo = await geocoding.geocodeAddress(c.address!);
            }
            final place = await places.create(
              Place(
                name: c.name,
                address: c.address,
                category: c.category,
                saveReason: c.reason,
                evidenceSummary: c.evidenceSummary,
                confidencePercent: c.confidencePercent,
                extractedAddress: c.postAddress ?? c.address,
                latitude: c.latitude ?? geo?.latitude,
                longitude: c.longitude ?? geo?.longitude,
                mapPinX: c.mapPinX,
                mapPinY: c.mapPinY,
                openingTimeMinutes: c.openingTimeMinutes,
                closingTimeMinutes: c.closingTimeMinutes,
                closedWeekdays: c.closedWeekdays,
              ),
              mapIds: [mapId],
            );
            if (c.genres.isNotEmpty) {
              final currentTags = await tags.tagsForPlace(place.id);
              await tags.setPlaceTags(
                placeId: place.id,
                tagNames: {
                  ...currentTags.map((tag) => tag.name),
                  ...c.genres,
                }.toList(),
              );
            }
            await sourcePosts.linkPlace(
              placeId: place.id,
              sourcePostId: sourcePostId,
            );
            created.add(place);
          }
          return created;
        }) ??
        const <Place>[];
  }

  Future<PinMap> createMap({
    required String name,
    String description = '',
    String icon = '📍',
    int themeColorValue = 0xFFE8F1EC,
  }) {
    return maps.create(
      PinMap(
        name: name,
        description: description,
        icon: icon,
        themeColorValue: themeColorValue,
      ),
    );
  }

  Future<PinMap> duplicateMap(String sourceMapId) async {
    final source = await maps.getById(sourceMapId);
    if (source == null) throw StateError('複製元のマップが見つかりません');
    final copy = await maps.create(
      PinMap(
        name: '${source.name}（コピー）',
        description: source.description,
        icon: source.icon,
        themeColorValue: source.themeColorValue,
        isPublic: false,
        allowsCollaboration: false,
      ),
    );
    try {
      final placesToCopy = await places.getByMapId(sourceMapId);
      for (final place in placesToCopy) {
        await places.create(
          Place(
            name: place.name,
            formalName: place.formalName,
            address: place.address,
            prefecture: place.prefecture,
            city: place.city,
            area: place.area,
            nearestStation: place.nearestStation,
            building: place.building,
            floor: place.floor,
            category: place.category,
            latitude: place.latitude,
            longitude: place.longitude,
            externalPlaceId: place.externalPlaceId,
            saveReason: place.saveReason,
            userMemo: place.userMemo,
            recommendedItems: place.recommendedItems,
            notesFromPost: place.notesFromPost,
            extractedAddress: place.extractedAddress,
            evidenceSummary: place.evidenceSummary,
            confidencePercent: place.confidencePercent,
            openingTimeMinutes: place.openingTimeMinutes,
            closingTimeMinutes: place.closingTimeMinutes,
            closedWeekdays: List.of(place.closedWeekdays),
            visitStatus: place.visitStatus,
            visitCount: place.visitCount,
            firstVisitedAt: place.firstVisitedAt,
            lastVisitedAt: place.lastVisitedAt,
            mapPinX: place.mapPinX,
            mapPinY: place.mapPinY,
          ),
          mapIds: [copy.id],
          allowDuplicate: true,
        );
      }
      return copy;
    } catch (_) {
      await maps.delete(copy.id);
      rethrow;
    }
  }

  Future<TripPlan> createAutoPlanFromMap(
    String mapId, {
    DateTime? startDate,
    int placesPerDay = 6,
  }) async {
    final map = await maps.getById(mapId);
    if (map == null) throw StateError('マップが見つかりません');
    final sourcePlaces = await places.getByMapId(mapId);
    if (sourcePlaces.isEmpty) throw StateError('日程に追加できる場所がありません');
    final ordered = _nearestNeighborOrder(sourcePlaces);
    final firstDay = PlanStop.dateOnly(startDate ?? DateTime.now());
    final plan = await plans.create(
      TripPlan(
        title: '${map.name}プラン',
        startDate: firstDay,
        notes: '場所同士の距離が近くなるよう自動配置しました。',
      ),
    );
    try {
      for (var i = 0; i < ordered.length; i++) {
        final day = firstDay.add(Duration(days: i ~/ placesPerDay));
        final current = ordered[i];
        final next = i + 1 < ordered.length ? ordered[i + 1] : null;
        await plans.addStop(
          PlanStop(
            planId: plan.id,
            placeId: current.id,
            dayDate: day,
            stayMinutes: 60,
            transitToNext: TransitMode.walk,
            transitMinutes: next == null
                ? null
                : _estimatedTransitMinutes(current, next),
          ),
        );
      }
      return plan;
    } catch (_) {
      await plans.delete(plan.id);
      rethrow;
    }
  }

  List<Place> _nearestNeighborOrder(List<Place> input) {
    final remaining = List<Place>.of(input);
    remaining.sort(
      (a, b) => (a.openingTimeMinutes ?? 24 * 60).compareTo(
        b.openingTimeMinutes ?? 24 * 60,
      ),
    );
    final ordered = <Place>[];
    while (remaining.isNotEmpty) {
      if (ordered.isEmpty) {
        ordered.add(remaining.removeAt(0));
        continue;
      }
      final last = ordered.last;
      remaining.sort(
        (a, b) => _distanceScore(last, a).compareTo(_distanceScore(last, b)),
      );
      ordered.add(remaining.removeAt(0));
    }
    return ordered;
  }

  double _distanceScore(Place a, Place b) {
    if (a.latitude == null ||
        a.longitude == null ||
        b.latitude == null ||
        b.longitude == null) {
      return double.maxFinite;
    }
    final lat = a.latitude! - b.latitude!;
    final lng = a.longitude! - b.longitude!;
    return lat * lat + lng * lng;
  }

  int _estimatedTransitMinutes(Place a, Place b) {
    final score = _distanceScore(a, b);
    if (!score.isFinite) return 20;
    return (score * 10000).clamp(8, 60).round();
  }

  int placeCountForMap(String mapId) {
    return hub.snapshot.mapPlaces.where((mp) => mp.mapId == mapId).length;
  }

  List<Place> queryPlaces({
    String query = '',
    PlaceFilterOption filter = PlaceFilterOption.all,
    PlaceSortOption sort = PlaceSortOption.registeredDesc,
    String? mapId,
  }) {
    Iterable<Place> list = hub.snapshot.places;
    if (mapId != null) {
      final ids = hub.snapshot.mapPlaces
          .where((mp) => mp.mapId == mapId)
          .map((mp) => mp.placeId)
          .toSet();
      list = list.where((p) => ids.contains(p.id));
    }

    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final postTitlesByPlace = <String, List<String>>{};
      for (final link in hub.snapshot.placeSources) {
        try {
          final post = hub.snapshot.sourcePosts.firstWhere(
            (p) => p.id == link.sourcePostId,
          );
          if (post.title != null) {
            postTitlesByPlace
                .putIfAbsent(link.placeId, () => [])
                .add(post.title!.toLowerCase());
          }
        } catch (_) {}
      }
      final tagsByPlace = <String, List<String>>{};
      for (final link in hub.snapshot.placeTags) {
        try {
          final tag = hub.snapshot.tags.firstWhere((t) => t.id == link.tagId);
          tagsByPlace
              .putIfAbsent(link.placeId, () => [])
              .add(tag.name.toLowerCase());
        } catch (_) {}
      }
      list = list.where((p) {
        final hay = [
          p.name,
          p.formalName,
          p.address,
          p.area,
          p.city,
          p.saveReason,
          p.userMemo,
          p.category,
          ...?postTitlesByPlace[p.id],
          ...?tagsByPlace[p.id],
        ].whereType<String>().join(' ').toLowerCase();
        return hay.contains(q);
      });
    }

    list = switch (filter) {
      PlaceFilterOption.all => list,
      PlaceFilterOption.unvisited => list.where((p) => !p.isVisited),
      PlaceFilterOption.visited => list.where((p) => p.isVisited),
      PlaceFilterOption.favorite => list.where((p) => p.isFavorite),
      PlaceFilterOption.nearby => list,
      PlaceFilterOption.openNow => list.where(
        (p) => p.isOpenAt(DateTime.now()),
      ),
    };

    final result = list.toList();
    result.sort((a, b) {
      return switch (sort) {
        PlaceSortOption.registeredDesc => b.createdAt.compareTo(a.createdAt),
        PlaceSortOption.updatedDesc => b.updatedAt.compareTo(a.updatedAt),
        PlaceSortOption.visitCountDesc => b.visitCount.compareTo(a.visitCount),
        PlaceSortOption.lastVisitedDesc =>
          (b.lastVisitedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            a.lastVisitedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
        PlaceSortOption.nameAsc => a.name.compareTo(b.name),
        PlaceSortOption.nearest => a.name.compareTo(b.name),
      };
    });
    return result;
  }
}
