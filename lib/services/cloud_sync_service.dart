import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../repositories/local_repositories.dart';

class PublicMapSummary {
  const PublicMapSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.placeCount,
  });
  final String id;
  final String name;
  final String description;
  final String icon;
  final int placeCount;
}

class ActiveMapShare {
  const ActiveMapShare({
    required this.token,
    required this.mapId,
    required this.mapName,
    required this.expiresAt,
    required this.createdAt,
  });

  final String token;
  final String mapId;
  final String mapName;
  final DateTime expiresAt;
  final DateTime createdAt;
}

class CloudSyncService {
  CloudSyncService({
    this.url = const String.fromEnvironment('SUPABASE_URL'),
    this.anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY'),
  });

  final String url;
  final String anonKey;
  bool _initialized = false;

  bool get isConfigured => url.startsWith('https://') && anonKey.isNotEmpty;
  SupabaseClient get _client => Supabase.instance.client;
  User? get user => _initialized ? _client.auth.currentUser : null;
  bool get hasRecoverableAccount => user?.email?.isNotEmpty == true;
  static const _lastSyncPrefix = 'cloud_last_sync_v1_';
  static const authCallbackUrl = 'pinlogy://auth-callback';

  Future<DateTime?> lastSyncAt() async {
    await _initialize();
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final preferences = await SharedPreferences.getInstance();
    return DateTime.tryParse(
      preferences.getString('$_lastSyncPrefix$userId') ?? '',
    );
  }

  Future<void> _initialize() async {
    if (!isConfigured) throw StateError('Supabaseが設定されていません');
    if (_initialized) return;
    await Supabase.initialize(url: url, publishableKey: anonKey);
    _initialized = true;
  }

  Stream<void> watchAuthChanges() async* {
    await _initialize();
    await for (final _ in _client.auth.onAuthStateChange) {
      yield null;
    }
  }

  Future<void> connect() async {
    await _initialize();
    if (_client.auth.currentUser == null) {
      try {
        await _client.auth.signInAnonymously();
      } on AuthException catch (error) {
        if (error.code == 'anonymous_provider_disabled') {
          throw StateError(
            'クラウド同期を使うには「アカウントを設定」から新規登録またはログインしてください。端末内のデータは消えていません。',
          );
        }
        rethrow;
      }
    }
    final id = _client.auth.currentUser!.id;
    await _client.from('users').upsert({
      'id': id,
      'is_anonymous': _client.auth.currentUser?.isAnonymous ?? true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await _cleanupIfNeeded(id);
  }

  Future<void> _cleanupIfNeeded(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    final key = 'cloud_cleanup_v1_$userId';
    final previous = DateTime.tryParse(preferences.getString(key) ?? '');
    if (previous != null && DateTime.now().difference(previous).inDays < 7) {
      return;
    }
    // 期限切れ共有コードと長期間未使用の匿名データを週1回だけ整理する。
    await _client.rpc('cleanup_stale_cloud_data');
    await preferences.setString(key, DateTime.now().toUtc().toIso8601String());
  }

  Future<void> registerAccount(String email, String password) async {
    await _initialize();
    final current = _client.auth.currentUser;
    if (current?.isAnonymous == true) {
      await _client.auth.updateUser(
        UserAttributes(email: email, password: password),
      );
    } else if (current == null) {
      await _client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: authCallbackUrl,
      );
    } else {
      throw StateError('すでにアカウントへログインしています');
    }
  }

  Future<void> signIn(String email, String password) async {
    await _initialize();
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> sendPasswordReset(String email) async {
    await _initialize();
    await _client.auth.resetPasswordForEmail(
      email,
      redirectTo: authCallbackUrl,
    );
  }

  Future<void> resendConfirmation(String email) async {
    await _initialize();
    await _client.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: authCallbackUrl,
    );
  }

  Future<void> signOut() async {
    await _initialize();
    await _client.auth.signOut();
  }

  Future<void> deleteAccount() async {
    await _initialize();
    if (_client.auth.currentUser == null) {
      throw StateError('ログインしているアカウントがありません');
    }
    await _client.rpc('delete_my_account');
    await _client.auth.signOut(scope: SignOutScope.local);
  }

  Future<void> sync(LocalRepositoryHub hub) async {
    await connect();
    final ownerId = user!.id;
    final preferences = await SharedPreferences.getInstance();
    final lastSyncValue = preferences.getString('$_lastSyncPrefix$ownerId');
    final lastSync = lastSyncValue == null
        ? null
        : DateTime.tryParse(lastSyncValue);
    // 同期開始時刻を保存することで、処理中に更新されたデータを次回取りこぼさない。
    final syncStartedAt = DateTime.now().toUtc();
    var snapshot = hub.snapshot;
    final pendingDeletes = List<String>.of(snapshot.pendingCloudDeletes);
    if (pendingDeletes.isNotEmpty) {
      for (final table in const [
        'plan_stops',
        'plans',
        'place_tags',
        'tags',
        'map_places',
        'places',
        'maps',
      ]) {
        final prefix = '$table:';
        final ids = pendingDeletes
            .where((entry) => entry.startsWith(prefix))
            .map((entry) => entry.substring(prefix.length))
            .where((id) => id.isNotEmpty)
            .toList();
        if (ids.isEmpty) continue;
        var query = _client.from(table).delete().inFilter('id', ids);
        if (table == 'places' ||
            table == 'maps' ||
            table == 'plans' ||
            table == 'tags') {
          query = query.eq('owner_id', ownerId);
        }
        await query;
      }
      await hub.acknowledgeCloudDeletes(pendingDeletes);
    }
    await pull(hub, updatedAfter: lastSync);
    snapshot = hub.snapshot;
    final sharedMapIds = snapshot.mapMembers
        .where((member) => member.userId == ownerId && member.role != 'owner')
        .map((member) => member.mapId)
        .toSet();
    final ownedMaps = snapshot.maps
        .where((map) => !sharedMapIds.contains(map.id))
        .where(
          (map) => lastSync == null || map.updatedAt.toUtc().isAfter(lastSync),
        )
        .toList();
    final allOwnedMapIds = snapshot.maps
        .where((map) => !sharedMapIds.contains(map.id))
        .map((map) => map.id)
        .toSet();
    final ownedPlaceIds = snapshot.mapPlaces
        .where((link) => allOwnedMapIds.contains(link.mapId))
        .map((link) => link.placeId)
        .toSet();

    if (ownedMaps.isNotEmpty) {
      await _client
          .from('maps')
          .upsert(ownedMaps.map((map) => _mapRow(map, ownerId)).toList());
    }
    final places = snapshot.places.where(
      (place) =>
          ownedPlaceIds.contains(place.id) &&
          (lastSync == null || place.updatedAt.toUtc().isAfter(lastSync)),
    );
    if (places.isNotEmpty) {
      await _client
          .from('places')
          .upsert(places.map((place) => _placeRow(place, ownerId)).toList());
    }
    final links = snapshot.mapPlaces.where(
      (link) => allOwnedMapIds.contains(link.mapId),
    );
    if (links.isNotEmpty) {
      await _client
          .from('map_places')
          .upsert(
            links
                .map(
                  (link) => {
                    'id': link.id,
                    'map_id': link.mapId,
                    'place_id': link.placeId,
                    'added_at': link.addedAt.toUtc().toIso8601String(),
                  },
                )
                .toList(),
          );
    }
    if (snapshot.tags.isNotEmpty) {
      await _client
          .from('tags')
          .upsert(
            snapshot.tags
                .map(
                  (tag) => {
                    'id': tag.id,
                    'owner_id': ownerId,
                    'name': tag.name,
                  },
                )
                .toList(),
          );
    }
    final placeTags = snapshot.placeTags.where(
      (link) => ownedPlaceIds.contains(link.placeId),
    );
    if (placeTags.isNotEmpty) {
      await _client
          .from('place_tags')
          .upsert(
            placeTags
                .map(
                  (link) => {
                    'id': link.id,
                    'place_id': link.placeId,
                    'tag_id': link.tagId,
                  },
                )
                .toList(),
          );
    }
    // 共有相手から元投稿へ戻れるよう、専用テーブルにはURL情報だけを送る。
    // 投稿本文・OCR・解析結果・端末画像・個人メモは構造上保存できない。
    final sourcePostsById = {
      for (final post in snapshot.sourcePosts) post.id: post,
    };
    final sourceLinksByPlace = <String, List<PlaceSource>>{};
    for (final link in snapshot.placeSources) {
      if (!ownedPlaceIds.contains(link.placeId)) continue;
      sourceLinksByPlace.putIfAbsent(link.placeId, () => []).add(link);
    }
    final safeSourceRows = <Map<String, dynamic>>[];
    for (final mapPlace in snapshot.mapPlaces) {
      if (!allOwnedMapIds.contains(mapPlace.mapId)) continue;
      for (final link in sourceLinksByPlace[mapPlace.placeId] ?? const []) {
        final post = sourcePostsById[link.sourcePostId];
        final sourceUri = Uri.tryParse(post?.url ?? '');
        if (post == null || sourceUri?.scheme != 'https') continue;
        safeSourceRows.add({
          'owner_id': ownerId,
          'map_id': mapPlace.mapId,
          'place_id': mapPlace.placeId,
          'source_post_id': post.id,
          'url': post.url,
          'service': post.service,
          'title': post.title,
          'received_at': post.receivedAt.toUtc().toIso8601String(),
          'created_at': post.createdAt.toUtc().toIso8601String(),
          'updated_at': post.updatedAt.toUtc().toIso8601String(),
        });
      }
    }
    if (safeSourceRows.isNotEmpty) {
      await _client
          .from('shared_source_links')
          .upsert(safeSourceRows, onConflict: 'map_id,place_id,source_post_id');
    }
    final changedPlans = snapshot.plans.where(
      (plan) => lastSync == null || plan.updatedAt.toUtc().isAfter(lastSync),
    );
    if (changedPlans.isNotEmpty) {
      await _client
          .from('plans')
          .upsert(
            changedPlans
                .map(
                  (plan) => {
                    'id': plan.id,
                    'owner_id': ownerId,
                    'title': plan.title,
                    'notes': plan.notes,
                    'start_date': plan.startDate
                        ?.toIso8601String()
                        .split('T')
                        .first,
                    'created_at': plan.createdAt.toUtc().toIso8601String(),
                    'updated_at': plan.updatedAt.toUtc().toIso8601String(),
                  },
                )
                .toList(),
          );
    }
    if (snapshot.planStops.isNotEmpty) {
      await _client
          .from('plan_stops')
          .upsert(
            snapshot.planStops
                .map(
                  (stop) => {
                    'id': stop.id,
                    'plan_id': stop.planId,
                    'place_id': stop.placeId,
                    'day_date': stop.dayDate
                        ?.toIso8601String()
                        .split('T')
                        .first,
                    'sort_order': stop.sortOrder,
                    'stay_minutes': stop.stayMinutes,
                    'transit_to_next': stop.transitToNext?.name,
                    'transit_minutes': stop.transitMinutes,
                    'note': stop.note,
                    'created_at': stop.createdAt.toUtc().toIso8601String(),
                  },
                )
                .toList(),
          );
    }
    await preferences.setString(
      '$_lastSyncPrefix$ownerId',
      syncStartedAt.toIso8601String(),
    );
  }

  Future<void> pull(LocalRepositoryHub hub, {DateTime? updatedAfter}) async {
    await connect();
    final cutoff = updatedAfter?.toUtc().toIso8601String();
    final mapRows = List<Map<String, dynamic>>.from(
      cutoff == null
          ? await _client.from('maps').select()
          : await _client.from('maps').select().gt('updated_at', cutoff),
    );
    final placeRows = List<Map<String, dynamic>>.from(
      cutoff == null
          ? await _client.from('places').select()
          : await _client.from('places').select().gt('updated_at', cutoff),
    );
    final linkRows = List<Map<String, dynamic>>.from(
      await _client.from('map_places').select(),
    );
    final memberRows = List<Map<String, dynamic>>.from(
      await _client.from('map_members').select(),
    );
    final safeSourceRows = List<Map<String, dynamic>>.from(
      await _client.from('shared_source_links').select(),
    );
    final tagRows = List<Map<String, dynamic>>.from(
      await _client.from('tags').select(),
    );
    final placeTagRows = List<Map<String, dynamic>>.from(
      await _client.from('place_tags').select(),
    );
    final planRows = List<Map<String, dynamic>>.from(
      cutoff == null
          ? await _client.from('plans').select()
          : await _client.from('plans').select().gt('updated_at', cutoff),
    );
    final stopRows = List<Map<String, dynamic>>.from(
      await _client.from('plan_stops').select(),
    );
    await hub.mergeCloudData(
      maps: mapRows.map(_mapFromRow).toList(),
      places: placeRows.map(_placeFromRow).toList(),
      mapPlaces: linkRows
          .map(
            (row) => MapPlace(
              id: row['id'] as String,
              mapId: row['map_id'] as String,
              placeId: row['place_id'] as String,
              addedAt: DateTime.parse(row['added_at'] as String),
            ),
          )
          .toList(),
      mapMembers: memberRows
          .map(
            (row) => MapMember(
              id: row['id'] as String,
              mapId: row['map_id'] as String,
              userId: row['user_id'] as String,
              role: row['role'] as String,
              joinedAt: DateTime.parse(row['joined_at'] as String),
            ),
          )
          .toList(),
      sourcePosts: safeSourceRows
          .where((row) => row['owner_id'] != user?.id)
          .map(
            (row) => SourcePost(
              id: row['source_post_id'] as String,
              url: row['url'] as String,
              service: row['service'] as String?,
              title: row['title'] as String?,
              body: null,
              imagePaths: const [],
              receivedAt: DateTime.parse(row['received_at'] as String),
              createdAt: DateTime.parse(row['created_at'] as String),
              updatedAt: DateTime.parse(row['updated_at'] as String),
            ),
          )
          .toList(),
      placeSources: safeSourceRows
          .where((row) => row['owner_id'] != user?.id)
          .map(
            (row) => PlaceSource(
              id: row['id'] as String,
              placeId: row['place_id'] as String,
              sourcePostId: row['source_post_id'] as String,
              linkedAt: DateTime.parse(row['created_at'] as String),
            ),
          )
          .toList(),
      tags: tagRows
          .map(
            (row) => Tag(id: row['id'] as String, name: row['name'] as String),
          )
          .toList(),
      placeTags: placeTagRows
          .map(
            (row) => PlaceTag(
              id: row['id'] as String,
              placeId: row['place_id'] as String,
              tagId: row['tag_id'] as String,
            ),
          )
          .toList(),
      plans: planRows
          .map(
            (row) => TripPlan(
              id: row['id'] as String,
              title: row['title'] as String?,
              notes: row['notes'] as String?,
              startDate: row['start_date'] == null
                  ? null
                  : DateTime.parse(row['start_date'] as String),
              createdAt: DateTime.parse(row['created_at'] as String),
              updatedAt: DateTime.parse(row['updated_at'] as String),
            ),
          )
          .toList(),
      planStops: stopRows
          .map(
            (row) => PlanStop(
              id: row['id'] as String,
              planId: row['plan_id'] as String,
              placeId: row['place_id'] as String,
              dayDate: row['day_date'] == null
                  ? null
                  : DateTime.parse(row['day_date'] as String),
              sortOrder: row['sort_order'] as int? ?? 0,
              stayMinutes: row['stay_minutes'] as int?,
              transitToNext: TransitMode.fromName(
                row['transit_to_next'] as String?,
              ),
              transitMinutes: row['transit_minutes'] as int?,
              note: row['note'] as String?,
              createdAt: DateTime.parse(row['created_at'] as String),
            ),
          )
          .toList(),
    );
  }

  Future<String> createShareCode(String mapId, {bool editable = false}) async {
    await connect();
    final value = await _client.rpc(
      'create_map_share',
      params: {
        'target_map_id': mapId,
        'share_role': editable ? 'editor' : 'viewer',
      },
    );
    return value.toString();
  }

  Uri mapShareUri(String code) => Uri(
    scheme: 'pinlogy',
    host: 'map-share',
    queryParameters: {'code': code.trim()},
  );

  String? shareCodeFromText(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri?.scheme == 'pinlogy' && uri?.host == 'map-share') {
      final code = uri?.queryParameters['code']?.trim();
      return code == null || code.isEmpty ? null : code;
    }
    final match = RegExp(
      r'pinlogy://map-share\?[^\s]*code=([^\s&]+)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match != null) return Uri.decodeComponent(match.group(1)!);
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<List<ActiveMapShare>> activeMapShares() async {
    await connect();
    final rows = List<Map<String, dynamic>>.from(
      await _client.rpc('list_my_map_shares'),
    );
    return rows
        .map(
          (row) => ActiveMapShare(
            token: row['token'] as String,
            mapId: row['map_id'] as String,
            mapName: row['map_name'] as String,
            expiresAt: DateTime.parse(row['expires_at'] as String),
            createdAt: DateTime.parse(row['created_at'] as String),
          ),
        )
        .toList();
  }

  Future<void> revokeMapShare(String token) async {
    await connect();
    await _client.rpc('revoke_map_share', params: {'share_token': token});
  }

  Future<void> acceptShareCode(LocalRepositoryHub hub, String code) async {
    await connect();
    final token = shareCodeFromText(code);
    if (token == null) throw StateError('共有リンクまたは共有コードを確認してください');
    await _client.rpc('accept_map_share', params: {'share_token': token});
    await pull(hub);
  }

  Future<List<PublicMapSummary>> publicMaps({
    int limit = 30,
    int offset = 0,
  }) async {
    await connect();
    final rows = List<Map<String, dynamic>>.from(
      await _client.rpc(
        'list_public_maps',
        params: {
          'page_limit': limit.clamp(1, 50),
          'page_offset': offset < 0 ? 0 : offset,
        },
      ),
    );
    return rows
        .map(
          (row) => PublicMapSummary(
            id: row['id'] as String,
            name: row['name'] as String,
            description: row['description'] as String? ?? '',
            icon: row['icon'] as String? ?? '🗺️',
            placeCount: (row['place_count'] as num? ?? 0).toInt(),
          ),
        )
        .toList();
  }

  Future<void> clonePublicMap(LocalRepositoryHub hub, String mapId) async {
    await connect();
    await _client.rpc('clone_public_map', params: {'source_map_id': mapId});
    await pull(hub);
  }

  Map<String, dynamic> _mapRow(PinMap map, String ownerId) => {
    'id': map.id,
    'owner_id': ownerId,
    'name': map.name,
    'description': map.description,
    'icon': map.icon,
    'theme_color': map.themeColorValue,
    'is_public': map.isPublic,
    'allows_collaboration': map.allowsCollaboration,
    'last_latitude': map.lastLatitude,
    'last_longitude': map.lastLongitude,
    'last_zoom': map.lastZoom,
    'created_at': map.createdAt.toUtc().toIso8601String(),
    'updated_at': map.updatedAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> _placeRow(Place place, String ownerId) => {
    'id': place.id,
    'owner_id': ownerId,
    'name': place.name,
    'formal_name': place.formalName,
    'address': place.address,
    'prefecture': place.prefecture,
    'city': place.city,
    'area': place.area,
    'nearest_station': place.nearestStation,
    'building': place.building,
    'floor': place.floor,
    'category': place.category,
    'latitude': place.latitude,
    'longitude': place.longitude,
    'external_place_id': place.externalPlaceId,
    'save_reason': place.saveReason,
    'opening_time_minutes': place.openingTimeMinutes,
    'closing_time_minutes': place.closingTimeMinutes,
    'closed_weekdays': place.closedWeekdays,
    'visit_status': place.visitStatus.name,
    'visit_count': place.visitCount,
    'first_visited_at': place.firstVisitedAt?.toUtc().toIso8601String(),
    'last_visited_at': place.lastVisitedAt?.toUtc().toIso8601String(),
    'created_at': place.createdAt.toUtc().toIso8601String(),
    'updated_at': place.updatedAt.toUtc().toIso8601String(),
  };

  PinMap _mapFromRow(Map<String, dynamic> row) => PinMap(
    id: row['id'] as String,
    name: row['name'] as String,
    description: row['description'] as String? ?? '',
    icon: row['icon'] as String? ?? '📍',
    themeColorValue: row['theme_color'] as int? ?? 0xFFE8F1EC,
    isPublic: row['is_public'] as bool? ?? false,
    allowsCollaboration: row['allows_collaboration'] as bool? ?? false,
    lastLatitude: (row['last_latitude'] as num?)?.toDouble(),
    lastLongitude: (row['last_longitude'] as num?)?.toDouble(),
    lastZoom: (row['last_zoom'] as num?)?.toDouble(),
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
  );

  Place _placeFromRow(Map<String, dynamic> row) => Place(
    id: row['id'] as String,
    name: row['name'] as String,
    formalName: row['formal_name'] as String?,
    address: row['address'] as String?,
    prefecture: row['prefecture'] as String?,
    city: row['city'] as String?,
    area: row['area'] as String?,
    nearestStation: row['nearest_station'] as String?,
    building: row['building'] as String?,
    floor: row['floor'] as String?,
    category: row['category'] as String?,
    latitude: (row['latitude'] as num?)?.toDouble(),
    longitude: (row['longitude'] as num?)?.toDouble(),
    externalPlaceId: row['external_place_id'] as String?,
    saveReason: row['save_reason'] as String?,
    openingTimeMinutes: row['opening_time_minutes'] as int?,
    closingTimeMinutes: row['closing_time_minutes'] as int?,
    closedWeekdays: ((row['closed_weekdays'] as List?) ?? const [])
        .whereType<num>()
        .map((value) => value.toInt())
        .toList(),
    visitStatus: VisitStatus.fromName(row['visit_status'] as String?),
    visitCount: row['visit_count'] as int? ?? 0,
    firstVisitedAt: row['first_visited_at'] == null
        ? null
        : DateTime.parse(row['first_visited_at'] as String),
    lastVisitedAt: row['last_visited_at'] == null
        ? null
        : DateTime.parse(row['last_visited_at'] as String),
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
  );
}
