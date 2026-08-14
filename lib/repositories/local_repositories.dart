import 'dart:convert';

import '../core/ids.dart';
import '../models/models.dart';
import 'local_data_store.dart';
import 'repository_interfaces.dart';

typedef SnapshotListener = void Function();

/// 単一のローカルスナップショットを共有するリポジトリ実装群のハブ。
class LocalRepositoryHub {
  LocalRepositoryHub(this.store);

  final LocalDataStore store;
  AppSnapshot _snapshot = AppSnapshot();
  final List<SnapshotListener> _listeners = [];
  bool _loaded = false;

  MapRepository get maps => _LocalMapRepository(this);
  PlaceRepository get places => _LocalPlaceRepository(this);
  SourcePostRepository get sourcePosts => _LocalSourcePostRepository(this);
  AnalysisRepository get analysis => _LocalAnalysisRepository(this);
  VisitRepository get visits => _LocalVisitRepository(this);
  TagRepository get tags => _LocalTagRepository(this);
  PlanRepository get plans => _LocalPlanRepository(this);

  AppSnapshot get snapshot => _snapshot;

  void addListener(SnapshotListener listener) => _listeners.add(listener);
  void removeListener(SnapshotListener listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  Future<void> load({bool seedIfEmpty = true}) async {
    _snapshot = await store.load();
    if (seedIfEmpty && _snapshot.maps.isEmpty) {
      _snapshot = buildSeedSnapshot();
      await store.save(_snapshot);
    }
    _loaded = true;
    _notify();
  }

  Future<void> reload() async {
    _snapshot = await store.load();
    _loaded = true;
    _notify();
  }

  /// クラウド取得分をID単位で統合する。端末にしかないデータは削除しない。
  Future<void> mergeCloudData({
    required List<PinMap> maps,
    required List<Place> places,
    required List<MapPlace> mapPlaces,
    required List<MapMember> mapMembers,
    List<SourcePost> sourcePosts = const [],
    List<PlaceSource> placeSources = const [],
    List<Tag> tags = const [],
    List<PlaceTag> placeTags = const [],
    List<TripPlan> plans = const [],
    List<PlanStop> planStops = const [],
  }) async {
    List<T> merge<T>(List<T> local, List<T> remote, String Function(T) idOf) {
      final values = <String, T>{for (final item in local) idOf(item): item};
      for (final item in remote) {
        values[idOf(item)] = item;
      }
      return values.values.toList();
    }

    List<T> mergeLatest<T>(
      List<T> local,
      List<T> remote,
      String Function(T) idOf,
      DateTime Function(T) updatedAt,
    ) {
      final values = <String, T>{for (final item in local) idOf(item): item};
      for (final item in remote) {
        final existing = values[idOf(item)];
        if (existing == null || !updatedAt(existing).isAfter(updatedAt(item))) {
          values[idOf(item)] = item;
        }
      }
      return values.values.toList();
    }

    for (final remote in places) {
      Place? local;
      for (final candidate in _snapshot.places) {
        if (candidate.id == remote.id) {
          local = candidate;
          break;
        }
      }
      if (local != null) {
        // クラウド同期対象外の個人情報は、同じIDでも端末側を維持する。
        remote.userMemo = local.userMemo;
        remote.recommendedItems = local.recommendedItems;
        remote.notesFromPost = local.notesFromPost;
        remote.evidenceSummary = local.evidenceSummary;
        remote.confidencePercent = local.confidencePercent;
        remote.coverImagePath = local.coverImagePath;
      }
    }

    for (final remote in sourcePosts) {
      SourcePost? local;
      for (final candidate in _snapshot.sourcePosts) {
        if (candidate.id == remote.id) {
          local = candidate;
          break;
        }
      }
      if (local != null) {
        remote.body = local.body;
        remote.userMemo = local.userMemo;
        remote.userCategories = local.userCategories;
        remote.userCategoriesSet = local.userCategoriesSet;
        remote.imagePaths = local.imagePaths;
      }
    }

    _snapshot = AppSnapshot(
      maps: mergeLatest(
        _snapshot.maps,
        maps,
        (item) => item.id,
        (item) => item.updatedAt,
      ),
      places: mergeLatest(
        _snapshot.places,
        places,
        (item) => item.id,
        (item) => item.updatedAt,
      ),
      mapPlaces: merge(_snapshot.mapPlaces, mapPlaces, (item) => item.id),
      mapMembers: merge(_snapshot.mapMembers, mapMembers, (item) => item.id),
      sourcePosts: mergeLatest(
        _snapshot.sourcePosts,
        sourcePosts,
        (item) => item.id,
        (item) => item.updatedAt,
      ),
      placeSources: merge(
        _snapshot.placeSources,
        placeSources,
        (item) => item.id,
      ),
      analysisJobs: _snapshot.analysisJobs,
      tags: merge(_snapshot.tags, tags, (item) => item.id),
      placeTags: merge(_snapshot.placeTags, placeTags, (item) => item.id),
      plans: mergeLatest(
        _snapshot.plans,
        plans,
        (item) => item.id,
        (item) => item.updatedAt,
      ),
      planStops: merge(_snapshot.planStops, planStops, (item) => item.id),
      pendingCloudDeletes: _snapshot.pendingCloudDeletes,
    );
    await store.save(_snapshot);
    _notify();
  }

  Future<void> _persist() async {
    try {
      await store.save(_snapshot);
      _notify();
    } catch (_) {
      _snapshot = await store.load();
      _notify();
      rethrow;
    }
  }

  Future<void> acknowledgeCloudDeletes(Iterable<String> entries) async {
    _snapshot.pendingCloudDeletes.removeWhere(entries.toSet().contains);
    await _persist();
  }

  void _queueCloudDelete(String table, String id) {
    final entry = '$table:$id';
    if (!_snapshot.pendingCloudDeletes.contains(entry)) {
      _snapshot.pendingCloudDeletes.add(entry);
    }
  }

  bool get isLoaded => _loaded;
}

class _LocalMapRepository implements MapRepository {
  _LocalMapRepository(this.hub);
  final LocalRepositoryHub hub;

  @override
  Future<List<PinMap>> getAll() async {
    final list = List<PinMap>.of(hub._snapshot.maps);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<PinMap?> getById(String id) async {
    try {
      return hub._snapshot.maps.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<PinMap> create(PinMap map) async {
    hub._snapshot.maps.add(map);
    await hub._persist();
    return map;
  }

  @override
  Future<PinMap> update(PinMap map) async {
    final index = hub._snapshot.maps.indexWhere((m) => m.id == map.id);
    if (index < 0) {
      throw StateError('マップが見つかりません');
    }
    final updated = map.copyWith(updatedAt: DateTime.now());
    hub._snapshot.maps[index] = updated;
    await hub._persist();
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    hub._queueCloudDelete('maps', id);
    hub._snapshot.maps.removeWhere((m) => m.id == id);
    hub._snapshot.mapPlaces.removeWhere((mp) => mp.mapId == id);
    hub._snapshot.mapMembers.removeWhere((mm) => mm.mapId == id);
    await hub._persist();
  }
}

class _LocalPlaceRepository implements PlaceRepository {
  _LocalPlaceRepository(this.hub);
  final LocalRepositoryHub hub;

  @override
  Future<List<Place>> getAll() async => List.of(hub._snapshot.places);

  @override
  Future<Place?> getById(String id) async {
    try {
      return hub._snapshot.places.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Place>> getByMapId(String mapId) async {
    final placeIds = hub._snapshot.mapPlaces
        .where((mp) => mp.mapId == mapId)
        .map((mp) => mp.placeId)
        .toSet();
    return hub._snapshot.places.where((p) => placeIds.contains(p.id)).toList();
  }

  @override
  Future<Place> create(
    Place place, {
    List<String> mapIds = const [],
    bool allowDuplicate = false,
  }) async {
    final existing = allowDuplicate ? null : _findDuplicate(place);
    late final Place target;
    if (existing == null) {
      hub._snapshot.places.add(place);
      target = place;
    } else {
      // 複製せず既存場所へマージ
      target = existing.copyWith(
        address: _prefer(existing.address, place.address),
        formalName: _prefer(existing.formalName, place.formalName),
        category: _prefer(existing.category, place.category),
        saveReason: _prefer(existing.saveReason, place.saveReason),
        userMemo: _prefer(existing.userMemo, place.userMemo),
        recommendedItems: _prefer(
          existing.recommendedItems,
          place.recommendedItems,
        ),
        notesFromPost: _prefer(existing.notesFromPost, place.notesFromPost),
        extractedAddress: _prefer(
          existing.extractedAddress,
          place.extractedAddress,
        ),
        evidenceSummary: _prefer(
          existing.evidenceSummary,
          place.evidenceSummary,
        ),
        confidencePercent:
            existing.confidencePercent ?? place.confidencePercent,
        openingTimeMinutes:
            existing.openingTimeMinutes ?? place.openingTimeMinutes,
        closingTimeMinutes:
            existing.closingTimeMinutes ?? place.closingTimeMinutes,
        closedWeekdays: existing.closedWeekdays.isNotEmpty
            ? existing.closedWeekdays
            : place.closedWeekdays,
        latitude: existing.latitude ?? place.latitude,
        longitude: existing.longitude ?? place.longitude,
        externalPlaceId: _prefer(
          existing.externalPlaceId,
          place.externalPlaceId,
        ),
        mapPinX: existing.mapPinX ?? place.mapPinX,
        mapPinY: existing.mapPinY ?? place.mapPinY,
        updatedAt: DateTime.now(),
      );
      final index = hub._snapshot.places.indexWhere((p) => p.id == existing.id);
      hub._snapshot.places[index] = target;
    }
    for (final mapId in mapIds) {
      final already = hub._snapshot.mapPlaces.any(
        (mp) => mp.mapId == mapId && mp.placeId == target.id,
      );
      if (!already) {
        hub._snapshot.mapPlaces.add(MapPlace(mapId: mapId, placeId: target.id));
      }
    }
    await hub._persist();
    return target;
  }

  Place? _findDuplicate(Place place) {
    final name = _normalize(place.name);
    final address = _normalize(place.address);
    for (final p in hub._snapshot.places) {
      if (place.externalPlaceId != null &&
          place.externalPlaceId!.isNotEmpty &&
          p.externalPlaceId == place.externalPlaceId) {
        return p;
      }
      if (_normalize(p.name) != name) continue;
      final existingAddress = _normalize(p.address);
      if (address.isEmpty ||
          existingAddress.isEmpty ||
          existingAddress == address) {
        return p;
      }
    }
    return null;
  }

  String _normalize(String? value) {
    if (value == null) return '';
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('　', '');
  }

  String? _prefer(String? current, String? incoming) {
    if (current != null && current.trim().isNotEmpty) return current;
    if (incoming != null && incoming.trim().isNotEmpty) return incoming;
    return current ?? incoming;
  }

  @override
  Future<Place> update(Place place) async {
    final index = hub._snapshot.places.indexWhere((p) => p.id == place.id);
    if (index < 0) {
      throw StateError('場所が見つかりません');
    }
    final updated = place.copyWith(updatedAt: DateTime.now());
    hub._snapshot.places[index] = updated;
    await hub._persist();
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    hub._queueCloudDelete('places', id);
    hub._snapshot.places.removeWhere((p) => p.id == id);
    hub._snapshot.mapPlaces.removeWhere((mp) => mp.placeId == id);
    hub._snapshot.placeSources.removeWhere((ps) => ps.placeId == id);
    hub._snapshot.placeTags.removeWhere((pt) => pt.placeId == id);
    hub._snapshot.planStops.removeWhere((ps) => ps.placeId == id);
    await hub._persist();
  }

  @override
  Future<void> addToMap({
    required String placeId,
    required String mapId,
  }) async {
    final exists = hub._snapshot.mapPlaces.any(
      (mp) => mp.mapId == mapId && mp.placeId == placeId,
    );
    if (!exists) {
      hub._snapshot.mapPlaces.add(MapPlace(mapId: mapId, placeId: placeId));
      final mapIndex = hub._snapshot.maps.indexWhere((m) => m.id == mapId);
      if (mapIndex >= 0) {
        hub._snapshot.maps[mapIndex] = hub._snapshot.maps[mapIndex].copyWith(
          updatedAt: DateTime.now(),
        );
      }
      await hub._persist();
    }
  }

  @override
  Future<void> removeFromMap({
    required String placeId,
    required String mapId,
  }) async {
    final removed = hub._snapshot.mapPlaces
        .where((mp) => mp.mapId == mapId && mp.placeId == placeId)
        .toList();
    for (final link in removed) {
      hub._queueCloudDelete('map_places', link.id);
    }
    hub._snapshot.mapPlaces.removeWhere(
      (mp) => mp.mapId == mapId && mp.placeId == placeId,
    );
    await hub._persist();
  }

  @override
  Future<List<PinMap>> mapsForPlace(String placeId) async {
    final mapIds = hub._snapshot.mapPlaces
        .where((mp) => mp.placeId == placeId)
        .map((mp) => mp.mapId)
        .toSet();
    return hub._snapshot.maps.where((m) => mapIds.contains(m.id)).toList();
  }

  @override
  Future<Place> markVisited(String placeId) async {
    return hub.visits.markVisited(placeId);
  }

  @override
  Future<List<Place>> search({
    String query = '',
    PlaceFilterOption filter = PlaceFilterOption.all,
    PlaceSortOption sort = PlaceSortOption.registeredDesc,
    String? mapId,
  }) async {
    Iterable<Place> list = hub._snapshot.places;
    if (mapId != null) {
      final ids = hub._snapshot.mapPlaces
          .where((mp) => mp.mapId == mapId)
          .map((mp) => mp.placeId)
          .toSet();
      list = list.where((p) => ids.contains(p.id));
    }

    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final postTitlesByPlace = <String, List<String>>{};
      for (final link in hub._snapshot.placeSources) {
        final post = hub._snapshot.sourcePosts.cast<SourcePost?>().firstWhere(
          (p) => p!.id == link.sourcePostId,
          orElse: () => null,
        );
        if (post?.title != null) {
          postTitlesByPlace
              .putIfAbsent(link.placeId, () => [])
              .add(post!.title!.toLowerCase());
        }
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
        ].whereType<String>().join(' ').toLowerCase();
        return hay.contains(q);
      });
    }

    list = switch (filter) {
      PlaceFilterOption.all => list,
      PlaceFilterOption.unvisited => list.where((p) => !p.isVisited),
      PlaceFilterOption.visited => list.where((p) => p.isVisited),
      PlaceFilterOption.favorite => list.where((p) => p.isFavorite),
      PlaceFilterOption.nearby => list, // 座標API未接続時はフィルタのみ通す
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

class _LocalSourcePostRepository implements SourcePostRepository {
  _LocalSourcePostRepository(this.hub);
  final LocalRepositoryHub hub;

  @override
  Future<List<SourcePost>> getAll() async {
    final list = List<SourcePost>.of(hub._snapshot.sourcePosts);
    list.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return list;
  }

  @override
  Future<SourcePost?> getById(String id) async {
    try {
      return hub._snapshot.sourcePosts.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SourcePost> create(SourcePost post) async {
    hub._snapshot.sourcePosts.add(post);
    await hub._persist();
    return post;
  }

  @override
  Future<SourcePost> update(SourcePost post) async {
    final index = hub._snapshot.sourcePosts.indexWhere((p) => p.id == post.id);
    if (index < 0) {
      throw StateError('投稿が見つかりません');
    }
    hub._snapshot.sourcePosts[index] = post.copyWith(updatedAt: DateTime.now());
    await hub._persist();
    return hub._snapshot.sourcePosts[index];
  }

  @override
  Future<void> delete(String id) async {
    hub._snapshot.sourcePosts.removeWhere((p) => p.id == id);
    hub._snapshot.placeSources.removeWhere((ps) => ps.sourcePostId == id);
    hub._snapshot.analysisJobs.removeWhere((j) => j.sourcePostId == id);
    await hub._persist();
  }

  @override
  Future<List<SourcePost>> postsForPlace(String placeId) async {
    final ids = hub._snapshot.placeSources
        .where((ps) => ps.placeId == placeId)
        .map((ps) => ps.sourcePostId)
        .toSet();
    return hub._snapshot.sourcePosts.where((p) => ids.contains(p.id)).toList();
  }

  @override
  Future<void> linkPlace({
    required String placeId,
    required String sourcePostId,
  }) async {
    final exists = hub._snapshot.placeSources.any(
      (ps) => ps.placeId == placeId && ps.sourcePostId == sourcePostId,
    );
    if (!exists) {
      hub._snapshot.placeSources.add(
        PlaceSource(placeId: placeId, sourcePostId: sourcePostId),
      );
      await hub._persist();
    }
  }
}

class _LocalAnalysisRepository implements AnalysisRepository {
  _LocalAnalysisRepository(this.hub);
  final LocalRepositoryHub hub;

  @override
  Future<List<AnalysisJob>> getAll() async {
    final list = List<AnalysisJob>.of(hub._snapshot.analysisJobs);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<AnalysisJob?> getBySourcePostId(String sourcePostId) async {
    try {
      return hub._snapshot.analysisJobs.firstWhere(
        (j) => j.sourcePostId == sourcePostId,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AnalysisJob> enqueue(String sourcePostId) async {
    final existing = await getBySourcePostId(sourcePostId);
    if (existing != null) {
      return existing;
    }
    final job = AnalysisJob(sourcePostId: sourcePostId);
    hub._snapshot.analysisJobs.add(job);
    await hub._persist();
    return job;
  }

  @override
  Future<AnalysisJob> update(AnalysisJob job) async {
    final index = hub._snapshot.analysisJobs.indexWhere((j) => j.id == job.id);
    if (index < 0) {
      throw StateError('解析ジョブが見つかりません');
    }
    final updated = job.copyWith(updatedAt: DateTime.now());
    hub._snapshot.analysisJobs[index] = updated;
    await hub._persist();
    return updated;
  }

  @override
  Future<void> cancel(String jobId) async {
    final index = hub._snapshot.analysisJobs.indexWhere((j) => j.id == jobId);
    if (index < 0) return;
    hub._snapshot.analysisJobs[index] = hub._snapshot.analysisJobs[index]
        .copyWith(
          status: AnalysisJobStatus.cancelled,
          updatedAt: DateTime.now(),
        );
    await hub._persist();
  }

  @override
  Future<void> retry(String jobId) async {
    final index = hub._snapshot.analysisJobs.indexWhere((j) => j.id == jobId);
    if (index < 0) return;
    hub._snapshot.analysisJobs[index] = hub._snapshot.analysisJobs[index]
        .copyWith(
          status: AnalysisJobStatus.pending,
          errorMessage: null,
          updatedAt: DateTime.now(),
        );
    await hub._persist();
  }
}

class _LocalTagRepository implements TagRepository {
  _LocalTagRepository(this.hub);
  final LocalRepositoryHub hub;

  @override
  Future<List<Tag>> getAll() async {
    final list = List<Tag>.of(hub._snapshot.tags);
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  @override
  Future<List<Tag>> tagsForPlace(String placeId) async {
    final ids = hub._snapshot.placeTags
        .where((pt) => pt.placeId == placeId)
        .map((pt) => pt.tagId)
        .toSet();
    return hub._snapshot.tags.where((t) => ids.contains(t.id)).toList();
  }

  @override
  Future<Tag> ensureTag(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('タグ名が空です');
    }
    try {
      return hub._snapshot.tags.firstWhere((t) => t.name == normalized);
    } catch (_) {
      final tag = Tag(name: normalized);
      hub._snapshot.tags.add(tag);
      await hub._persist();
      return tag;
    }
  }

  @override
  Future<void> setPlaceTags({
    required String placeId,
    required List<String> tagNames,
  }) async {
    final unique = tagNames
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    final tagIds = <String>[];
    for (final name in unique) {
      final tag = await ensureTag(name);
      tagIds.add(tag.id);
    }
    for (final link in hub._snapshot.placeTags.where(
      (pt) => pt.placeId == placeId,
    )) {
      hub._queueCloudDelete('place_tags', link.id);
    }
    hub._snapshot.placeTags.removeWhere((pt) => pt.placeId == placeId);
    for (final tagId in tagIds) {
      hub._snapshot.placeTags.add(PlaceTag(placeId: placeId, tagId: tagId));
    }
    await hub._persist();
  }

  @override
  Future<void> removeTagFromPlace({
    required String placeId,
    required String tagId,
  }) async {
    for (final link in hub._snapshot.placeTags.where(
      (pt) => pt.placeId == placeId && pt.tagId == tagId,
    )) {
      hub._queueCloudDelete('place_tags', link.id);
    }
    hub._snapshot.placeTags.removeWhere(
      (pt) => pt.placeId == placeId && pt.tagId == tagId,
    );
    await hub._persist();
  }
}

class _LocalVisitRepository implements VisitRepository {
  _LocalVisitRepository(this.hub);
  final LocalRepositoryHub hub;

  @override
  Future<Place> markVisited(String placeId) async {
    final index = hub._snapshot.places.indexWhere((p) => p.id == placeId);
    if (index < 0) {
      throw StateError('場所が見つかりません');
    }
    final now = DateTime.now();
    final current = hub._snapshot.places[index];
    final updated = current.copyWith(
      visitStatus: VisitStatus.visited,
      visitCount: current.visitCount + 1,
      firstVisitedAt: current.firstVisitedAt ?? now,
      lastVisitedAt: now,
      updatedAt: now,
    );
    hub._snapshot.places[index] = updated;
    await hub._persist();
    return updated;
  }

  @override
  Future<Place> setStatus(String placeId, VisitStatus status) async {
    final index = hub._snapshot.places.indexWhere((p) => p.id == placeId);
    if (index < 0) {
      throw StateError('場所が見つかりません');
    }
    final updated = hub._snapshot.places[index].copyWith(
      visitStatus: status,
      updatedAt: DateTime.now(),
    );
    hub._snapshot.places[index] = updated;
    await hub._persist();
    return updated;
  }
}

class _LocalPlanRepository implements PlanRepository {
  _LocalPlanRepository(this.hub);
  final LocalRepositoryHub hub;

  @override
  Future<List<TripPlan>> getAll() async {
    final list = List<TripPlan>.of(hub._snapshot.plans);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<TripPlan?> getById(String id) async {
    try {
      return hub._snapshot.plans.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<TripPlan> create(TripPlan plan) async {
    hub._snapshot.plans.add(plan);
    await hub._persist();
    return plan;
  }

  @override
  Future<TripPlan> update(TripPlan plan) async {
    final index = hub._snapshot.plans.indexWhere((p) => p.id == plan.id);
    if (index < 0) {
      throw StateError('プランが見つかりません');
    }
    final updated = plan.copyWith(updatedAt: DateTime.now());
    hub._snapshot.plans[index] = updated;
    await hub._persist();
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    for (final stop in hub._snapshot.planStops.where((s) => s.planId == id)) {
      hub._queueCloudDelete('plan_stops', stop.id);
    }
    hub._queueCloudDelete('plans', id);
    hub._snapshot.plans.removeWhere((p) => p.id == id);
    hub._snapshot.planStops.removeWhere((s) => s.planId == id);
    await hub._persist();
  }

  @override
  Future<List<PlanStop>> stopsForPlan(String planId) async {
    final stops =
        hub._snapshot.planStops.where((s) => s.planId == planId).toList()
          ..sort((a, b) {
            final day = _compareDay(a.dayDate, b.dayDate);
            if (day != 0) return day;
            return a.sortOrder.compareTo(b.sortOrder);
          });
    return stops;
  }

  @override
  Future<PlanStop> addStop(PlanStop stop) async {
    final day = stop.dayDate == null ? null : PlanStop.dateOnly(stop.dayDate!);
    final sameDay = hub._snapshot.planStops
        .where((s) => s.planId == stop.planId && _sameDay(s.dayDate, day))
        .toList();
    final nextOrder = sameDay.isEmpty
        ? 0
        : sameDay.map((s) => s.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    final created = stop.copyWith(
      dayDate: day,
      clearDayDate: day == null,
      sortOrder: nextOrder,
    );
    hub._snapshot.planStops.add(created);
    await _touchPlan(stop.planId);
    await hub._persist();
    return created;
  }

  @override
  Future<PlanStop> updateStop(PlanStop stop) async {
    final index = hub._snapshot.planStops.indexWhere((s) => s.id == stop.id);
    if (index < 0) {
      throw StateError('行程の地点が見つかりません');
    }
    final day = stop.dayDate == null ? null : PlanStop.dateOnly(stop.dayDate!);
    hub._snapshot.planStops[index] = stop.copyWith(
      dayDate: day,
      clearDayDate: day == null,
    );
    await _touchPlan(stop.planId);
    await hub._persist();
    return hub._snapshot.planStops[index];
  }

  @override
  Future<void> removeStop(String stopId) async {
    final index = hub._snapshot.planStops.indexWhere((s) => s.id == stopId);
    if (index < 0) return;
    final planId = hub._snapshot.planStops[index].planId;
    final day = hub._snapshot.planStops[index].dayDate;
    hub._queueCloudDelete('plan_stops', stopId);
    hub._snapshot.planStops.removeAt(index);
    await _reindexDay(planId, day);
    await _touchPlan(planId);
    await hub._persist();
  }

  @override
  Future<void> reorderStops({
    required String planId,
    DateTime? dayDate,
    required List<String> orderedStopIds,
  }) async {
    final day = dayDate == null ? null : PlanStop.dateOnly(dayDate);
    for (var i = 0; i < orderedStopIds.length; i++) {
      final index = hub._snapshot.planStops.indexWhere(
        (s) => s.id == orderedStopIds[i],
      );
      if (index < 0) continue;
      final stop = hub._snapshot.planStops[index];
      if (stop.planId != planId || !_sameDay(stop.dayDate, day)) continue;
      hub._snapshot.planStops[index] = stop.copyWith(sortOrder: i);
    }
    await _touchPlan(planId);
    await hub._persist();
  }

  Future<void> _reindexDay(String planId, DateTime? dayDate) async {
    final day = dayDate == null ? null : PlanStop.dateOnly(dayDate);
    final stops =
        hub._snapshot.planStops
            .where((s) => s.planId == planId && _sameDay(s.dayDate, day))
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (var i = 0; i < stops.length; i++) {
      final index = hub._snapshot.planStops.indexWhere(
        (s) => s.id == stops[i].id,
      );
      if (index >= 0) {
        hub._snapshot.planStops[index] = hub._snapshot.planStops[index]
            .copyWith(sortOrder: i);
      }
    }
  }

  Future<void> _touchPlan(String planId) async {
    final index = hub._snapshot.plans.indexWhere((p) => p.id == planId);
    if (index >= 0) {
      hub._snapshot.plans[index] = hub._snapshot.plans[index].copyWith(
        updatedAt: DateTime.now(),
      );
    }
  }

  static bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return PlanStop.dateOnly(a) == PlanStop.dateOnly(b);
  }

  static int _compareDay(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1; // 日付未定は後ろ
    if (b == null) return -1;
    return a.compareTo(b);
  }
}

AppSnapshot buildSeedSnapshot() {
  final mapFood = PinMap(
    id: 'map-food',
    name: 'ごはん屋',
    icon: '🍜',
    description: '東京・横浜を中心に',
    themeColorValue: 0xFFFFEEE5,
  );
  final mapHokkaido = PinMap(
    id: 'map-hokkaido',
    name: '北海道旅行',
    icon: '✈️',
    description: '2026年 冬',
    themeColorValue: 0xFFE5EFF9,
  );
  final mapCafe = PinMap(
    id: 'map-cafe',
    name: '東京カフェ',
    icon: '☕',
    description: '静かに過ごせるお店',
    themeColorValue: 0xFFF2E9DF,
  );
  final mapPhoto = PinMap(
    id: 'map-photo',
    name: '撮影スポット',
    icon: '📷',
    description: '景色と建築',
    themeColorValue: 0xFFE9E7F5,
  );

  final place1 = Place(
    id: 'place-soire',
    name: '喫茶ソワレ',
    address: '京都府京都市下京区西木屋町通四条上る真町95',
    prefecture: '京都府',
    city: '京都市下京区',
    category: '喫茶店',
    saveReason: '青い照明の店内とゼリーポンチが印象的',
    extractedAddress: '京都府京都市下京区西木屋町通四条上る真町95',
    evidenceSummary: '住所の取得元：投稿画像  ·  店名の取得元：投稿文',
    confidencePercent: 96,
    latitude: 34.9995,
    longitude: 135.7681,
    mapPinX: 0.24,
    mapPinY: 0.28,
  );
  final place2 = Place(
    id: 'place-kagi',
    name: '鍵善良房 四条本店',
    address: '京都府京都市東山区祇園町北側264',
    prefecture: '京都府',
    city: '京都市東山区',
    category: '和菓子',
    saveReason: '名物のくずきり。庭を眺められる奥の席',
    recommendedItems: 'くずきり',
    evidenceSummary: '住所の取得元：画像3枚目',
    confidencePercent: 93,
    latitude: 35.0036,
    longitude: 135.7784,
    mapPinX: 0.62,
    mapPinY: 0.45,
  );
  final place3 = Place(
    id: 'place-inoda',
    name: 'イノダコーヒ 本店',
    address: '京都府京都市中京区道祐町140',
    prefecture: '京都府',
    city: '京都市中京区',
    category: '喫茶店',
    saveReason: '朝食の京の朝食が投稿で紹介されていた',
    evidenceSummary: '住所の取得元：投稿文  ·  一致度要確認',
    confidencePercent: 78,
    visitStatus: VisitStatus.wantToGo,
    latitude: 35.0075,
    longitude: 135.7615,
    mapPinX: 0.42,
    mapPinY: 0.67,
  );

  final post = SourcePost(
    id: 'post-kyoto-5',
    url: 'https://www.instagram.com/p/example',
    service: 'Instagram',
    title: '京都で行きたい喫茶店5選',
    body: '京都で行きたい喫茶店5選。ソワレ、鍵善良房、イノダコーヒ…',
  );
  final postTiktok = SourcePost(
    id: 'post-hokkaido',
    url: 'https://www.tiktok.com/@example/video/1',
    service: 'TikTok',
    title: '北海道グルメまとめ',
    body: null,
  );
  final postShot = SourcePost(
    id: 'post-screenshot',
    service: 'スクリーンショット',
    title: '週末に行きたい場所',
    body: null,
  );

  final candidates = [
    ExtractionCandidate(
      name: '喫茶ソワレ',
      address: '京都府京都市下京区西木屋町通四条上る真町95',
      reason: '青い照明の店内とゼリーポンチが印象的',
      evidenceSummary: '住所の取得元：画像2枚目 / 店名の取得元：投稿文',
      confidencePercent: 96,
      match: PlaceMatchConfidence.high,
      mapPinX: 0.24,
      mapPinY: 0.28,
      latitude: 34.9995,
      longitude: 135.7681,
    ),
    ExtractionCandidate(
      name: '鍵善良房 四条本店',
      address: '京都府京都市東山区祇園町北側264',
      reason: '名物のくずきり。庭を眺められる奥の席',
      evidenceSummary: '住所の取得元：画像3枚目',
      confidencePercent: 93,
      match: PlaceMatchConfidence.high,
      mapPinX: 0.62,
      mapPinY: 0.45,
      latitude: 35.0036,
      longitude: 135.7784,
    ),
    ExtractionCandidate(
      name: 'イノダコーヒ 本店',
      address: '京都府京都市中京区道祐町140',
      reason: '朝食の京の朝食が投稿で紹介されていた',
      evidenceSummary: '住所の取得元：投稿文 / 店名検索との距離差あり',
      confidencePercent: 78,
      match: PlaceMatchConfidence.needsReview,
      hasAddressMismatch: true,
      postAddress: '京都府京都市中京区道祐町140',
      searchCandidateName: 'イノダコーヒ 三条支店',
      searchCandidateAddress: '京都府京都市中京区三条通河原町東入ル',
      mapPinX: 0.42,
      mapPinY: 0.67,
      latitude: 35.0075,
      longitude: 135.7615,
    ),
  ];

  return AppSnapshot(
    maps: [mapFood, mapHokkaido, mapCafe, mapPhoto],
    places: [place1, place2, place3],
    mapPlaces: [
      MapPlace(mapId: mapFood.id, placeId: place1.id),
      MapPlace(mapId: mapFood.id, placeId: place2.id),
      MapPlace(mapId: mapFood.id, placeId: place3.id),
      MapPlace(mapId: mapCafe.id, placeId: place1.id),
    ],
    sourcePosts: [post, postTiktok, postShot],
    placeSources: [
      PlaceSource(placeId: place1.id, sourcePostId: post.id),
      PlaceSource(placeId: place2.id, sourcePostId: post.id),
      PlaceSource(placeId: place3.id, sourcePostId: post.id),
    ],
    analysisJobs: [
      AnalysisJob(
        id: newId(),
        sourcePostId: post.id,
        status: AnalysisJobStatus.completed,
        resultJson: jsonEncode({
          'candidates': candidates.map((c) => c.toJson()).toList(),
        }),
      ),
      AnalysisJob(
        id: newId(),
        sourcePostId: postTiktok.id,
        status: AnalysisJobStatus.processing,
      ),
      AnalysisJob(
        id: newId(),
        sourcePostId: postShot.id,
        status: AnalysisJobStatus.completed,
        resultJson: jsonEncode({
          'candidates': [
            ExtractionCandidate(
              name: '週末カフェ候補',
              address: '東京都渋谷区',
              match: PlaceMatchConfidence.needsReview,
            ).toJson(),
            ExtractionCandidate(
              name: '公園の撮影ポイント',
              address: null,
              match: PlaceMatchConfidence.unresolved,
            ).toJson(),
          ],
        }),
      ),
    ],
    tags: [
      Tag(id: 'tag-cafe', name: 'カフェ'),
      Tag(id: 'tag-kyoto', name: '京都'),
      Tag(id: 'tag-sweet', name: 'スイーツ'),
    ],
    placeTags: [
      PlaceTag(placeId: place1.id, tagId: 'tag-cafe'),
      PlaceTag(placeId: place1.id, tagId: 'tag-kyoto'),
      PlaceTag(placeId: place2.id, tagId: 'tag-sweet'),
      PlaceTag(placeId: place2.id, tagId: 'tag-kyoto'),
    ],
    mapMembers: [
      MapMember(mapId: mapFood.id, userId: 'local-user', role: 'owner'),
      MapMember(mapId: mapHokkaido.id, userId: 'local-user', role: 'owner'),
      MapMember(mapId: mapCafe.id, userId: 'local-user', role: 'owner'),
      MapMember(mapId: mapPhoto.id, userId: 'local-user', role: 'owner'),
    ],
  );
}
