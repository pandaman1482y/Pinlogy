import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// アプリ全体のローカルデータスナップショット。
class AppSnapshot {
  AppSnapshot({
    List<PinMap>? maps,
    List<Place>? places,
    List<MapPlace>? mapPlaces,
    List<SourcePost>? sourcePosts,
    List<PlaceSource>? placeSources,
    List<AnalysisJob>? analysisJobs,
    List<Tag>? tags,
    List<PlaceTag>? placeTags,
    List<MapMember>? mapMembers,
    List<TripPlan>? plans,
    List<PlanStop>? planStops,
    List<String>? pendingCloudDeletes,
  }) : maps = maps ?? [],
       places = places ?? [],
       mapPlaces = mapPlaces ?? [],
       sourcePosts = sourcePosts ?? [],
       placeSources = placeSources ?? [],
       analysisJobs = analysisJobs ?? [],
       tags = tags ?? [],
       placeTags = placeTags ?? [],
       mapMembers = mapMembers ?? [],
       plans = plans ?? [],
       planStops = planStops ?? [],
       pendingCloudDeletes = pendingCloudDeletes ?? [];

  final List<PinMap> maps;
  final List<Place> places;
  final List<MapPlace> mapPlaces;
  final List<SourcePost> sourcePosts;
  final List<PlaceSource> placeSources;
  final List<AnalysisJob> analysisJobs;
  final List<Tag> tags;
  final List<PlaceTag> placeTags;
  final List<MapMember> mapMembers;
  final List<TripPlan> plans;
  final List<PlanStop> planStops;
  final List<String> pendingCloudDeletes;

  AppSnapshot copy() => AppSnapshot(
    maps: List.of(maps),
    places: List.of(places),
    mapPlaces: List.of(mapPlaces),
    sourcePosts: List.of(sourcePosts),
    placeSources: List.of(placeSources),
    analysisJobs: List.of(analysisJobs),
    tags: List.of(tags),
    placeTags: List.of(placeTags),
    mapMembers: List.of(mapMembers),
    plans: List.of(plans),
    planStops: List.of(planStops),
    pendingCloudDeletes: List.of(pendingCloudDeletes),
  );

  Map<String, dynamic> toJson() => {
    'maps': maps.map((e) => e.toJson()).toList(),
    'places': places.map((e) => e.toJson()).toList(),
    'mapPlaces': mapPlaces.map((e) => e.toJson()).toList(),
    'sourcePosts': sourcePosts.map((e) => e.toJson()).toList(),
    'placeSources': placeSources.map((e) => e.toJson()).toList(),
    'analysisJobs': analysisJobs.map((e) => e.toJson()).toList(),
    'tags': tags.map((e) => e.toJson()).toList(),
    'placeTags': placeTags.map((e) => e.toJson()).toList(),
    'mapMembers': mapMembers.map((e) => e.toJson()).toList(),
    'plans': plans.map((e) => e.toJson()).toList(),
    'planStops': planStops.map((e) => e.toJson()).toList(),
    'pendingCloudDeletes': pendingCloudDeletes,
  };

  factory AppSnapshot.fromJson(Map<String, dynamic> json) => AppSnapshot(
    maps: ((json['maps'] as List?) ?? const [])
        .map((e) => PinMap.fromJson(e as Map<String, dynamic>))
        .toList(),
    places: ((json['places'] as List?) ?? const [])
        .map((e) => Place.fromJson(e as Map<String, dynamic>))
        .toList(),
    mapPlaces: ((json['mapPlaces'] as List?) ?? const [])
        .map((e) => MapPlace.fromJson(e as Map<String, dynamic>))
        .toList(),
    sourcePosts: ((json['sourcePosts'] as List?) ?? const [])
        .map((e) => SourcePost.fromJson(e as Map<String, dynamic>))
        .toList(),
    placeSources: ((json['placeSources'] as List?) ?? const [])
        .map((e) => PlaceSource.fromJson(e as Map<String, dynamic>))
        .toList(),
    analysisJobs: ((json['analysisJobs'] as List?) ?? const [])
        .map((e) => AnalysisJob.fromJson(e as Map<String, dynamic>))
        .toList(),
    tags: ((json['tags'] as List?) ?? const [])
        .map((e) => Tag.fromJson(e as Map<String, dynamic>))
        .toList(),
    placeTags: ((json['placeTags'] as List?) ?? const [])
        .map((e) => PlaceTag.fromJson(e as Map<String, dynamic>))
        .toList(),
    mapMembers: ((json['mapMembers'] as List?) ?? const [])
        .map((e) => MapMember.fromJson(e as Map<String, dynamic>))
        .toList(),
    plans: ((json['plans'] as List?) ?? const [])
        .map((e) {
          if (e is! Map) return null;
          try {
            return TripPlan.fromJson(Map<String, dynamic>.from(e));
          } catch (_) {
            return null;
          }
        })
        .whereType<TripPlan>()
        .toList(),
    planStops: ((json['planStops'] as List?) ?? const [])
        .map((e) {
          if (e is! Map) return null;
          try {
            return PlanStop.fromJson(Map<String, dynamic>.from(e));
          } catch (_) {
            return null;
          }
        })
        .whereType<PlanStop>()
        .toList(),
    pendingCloudDeletes: ((json['pendingCloudDeletes'] as List?) ?? const [])
        .whereType<String>()
        .toList(),
  );
}

abstract class LocalDataStore {
  Future<AppSnapshot> load();
  Future<void> save(AppSnapshot snapshot);
}

class SharedPreferencesStore implements LocalDataStore {
  SharedPreferencesStore({this.prefsKey = 'pinlogy_snapshot_v1'});

  final String prefsKey;

  @override
  Future<AppSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) {
      return AppSnapshot();
    }
    try {
      return AppSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      final backup = prefs.getString('${prefsKey}_backup');
      if (backup == null || backup.isEmpty) rethrow;
      return AppSnapshot.fromJson(jsonDecode(backup) as Map<String, dynamic>);
    }
  }

  @override
  Future<void> save(AppSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString(prefsKey);
    if (previous != null && previous.isNotEmpty) {
      final backedUp = await prefs.setString('${prefsKey}_backup', previous);
      if (!backedUp) throw StateError('端末内バックアップの保存に失敗しました');
    }
    final saved = await prefs.setString(
      prefsKey,
      jsonEncode(snapshot.toJson()),
    );
    if (!saved) throw StateError('端末内データの保存に失敗しました');
  }
}

class InMemoryDataStore implements LocalDataStore {
  InMemoryDataStore([AppSnapshot? initial])
    : _snapshot = initial ?? AppSnapshot();

  AppSnapshot _snapshot;

  @override
  Future<AppSnapshot> load() async => _snapshot.copy();

  @override
  Future<void> save(AppSnapshot snapshot) async {
    _snapshot = snapshot.copy();
  }
}
