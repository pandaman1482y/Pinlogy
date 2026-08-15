import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/models/models.dart';
import 'package:pinlogy/repositories/local_data_store.dart';
import 'package:pinlogy/repositories/local_repositories.dart';

void main() {
  test('営業時間から今行けるか判定でき、日をまたぐ営業にも対応する', () {
    final daytime = Place(
      name: '昼カフェ',
      openingTimeMinutes: 10 * 60,
      closingTimeMinutes: 18 * 60,
      closedWeekdays: const [2],
    );
    expect(daytime.isOpenAt(DateTime(2026, 8, 3, 12)), isTrue);
    expect(daytime.isOpenAt(DateTime(2026, 8, 4, 12)), isFalse);

    final night = Place(
      name: '夜カフェ',
      openingTimeMinutes: 18 * 60,
      closingTimeMinutes: 2 * 60,
    );
    expect(night.isOpenAt(DateTime(2026, 8, 3, 23)), isTrue);
    expect(night.isOpenAt(DateTime(2026, 8, 3, 3)), isFalse);
  });
  late LocalRepositoryHub hub;

  setUp(() async {
    hub = LocalRepositoryHub(InMemoryDataStore());
    await hub.load(seedIfEmpty: false);
    await hub.maps.create(PinMap(id: 'm1', name: 'テストマップ', icon: '📍'));
    await hub.maps.create(PinMap(id: 'm2', name: '別マップ', icon: '☕'));
  });

  test('同じ場所は複製せず複数マップへ関連付けられる', () async {
    final first = await hub.places.create(
      Place(name: 'カフェA', address: '東京都渋谷区1-1-1'),
      mapIds: ['m1'],
    );
    final second = await hub.places.create(
      Place(name: 'カフェA', address: '東京都渋谷区1-1-1', saveReason: '夜景がきれい'),
      mapIds: ['m2'],
    );

    expect(second.id, first.id);
    expect(hub.snapshot.places.where((p) => p.name == 'カフェA').length, 1);
    expect(second.saveReason, '夜景がきれい');

    final maps = await hub.places.mapsForPlace(first.id);
    expect(maps.map((m) => m.id), containsAll(['m1', 'm2']));
  });

  test('表記ゆれのある同名同住所は重複統合される', () async {
    await hub.places.create(
      Place(name: '喫茶 ソワレ', address: '京都 市'),
      mapIds: ['m1'],
    );
    final merged = await hub.places.create(
      Place(name: '喫茶ソワレ', address: '京都市'),
      mapIds: ['m2'],
    );
    expect(hub.snapshot.places.length, 1);
    expect(merged.name, '喫茶 ソワレ');
  });

  test('タグを場所へ付与・更新できる', () async {
    final place = await hub.places.create(
      Place(name: 'タグテスト店'),
      mapIds: ['m1'],
    );
    await hub.tags.setPlaceTags(placeId: place.id, tagNames: ['カフェ', '夜景']);
    var tags = await hub.tags.tagsForPlace(place.id);
    expect(tags.map((t) => t.name), containsAll(['カフェ', '夜景']));

    await hub.tags.setPlaceTags(placeId: place.id, tagNames: ['カフェ']);
    tags = await hub.tags.tagsForPlace(place.id);
    expect(tags.map((t) => t.name), ['カフェ']);
  });

  test('訪問回数を増やせる', () async {
    final place = await hub.places.create(Place(name: '訪問店'), mapIds: ['m1']);
    final visited = await hub.visits.markVisited(place.id);
    expect(visited.visitCount, 1);
    expect(visited.isVisited, isTrue);
    final again = await hub.visits.markVisited(place.id);
    expect(again.visitCount, 2);
  });

  test('解析ジョブをキャンセル・再試行できる', () async {
    final post = await hub.sourcePosts.create(
      SourcePost(title: 'ジョブテスト', url: 'https://example.com'),
    );
    final job = await hub.analysis.enqueue(post.id);
    await hub.analysis.cancel(job.id);
    expect(
      (await hub.analysis.getBySourcePostId(post.id))?.status,
      AnalysisJobStatus.cancelled,
    );
    await hub.analysis.retry(job.id);
    expect(
      (await hub.analysis.getBySourcePostId(post.id))?.status,
      AnalysisJobStatus.pending,
    );
  });

  test('投稿本文と取り込みメモを分けて保存できる', () async {
    final post = await hub.sourcePosts.create(
      SourcePost(
        title: '喫茶ソワレ',
        body: 'TikTokから共有された投稿文',
        userMemo: '京都の青いゼリーのお店',
        userCategories: const ['カフェ', 'スイーツ'],
        userCategoriesSet: true,
      ),
    );
    final restored = AppSnapshot.fromJson(hub.snapshot.toJson());
    final saved = restored.sourcePosts.singleWhere(
      (item) => item.id == post.id,
    );

    expect(saved.body, 'TikTokから共有された投稿文');
    expect(saved.userMemo, '京都の青いゼリーのお店');
    expect(saved.userCategories, ['カフェ', 'スイーツ']);
    expect(saved.userCategoriesSet, isTrue);
  });

  test('投稿の代表画像を店名などと同じ投稿レコードに保持できる', () {
    final post = SourcePost(
      title: '画像を保持する店',
      imagePaths: const ['/support/source_media/post/image_0.jpg'],
      thumbnailPath: '/support/source_media/post/image_0.jpg',
    );

    final restored = SourcePost.fromJson(post.toJson());

    expect(restored.title, '画像を保持する店');
    expect(
      restored.displayThumbnailPath,
      '/support/source_media/post/image_0.jpg',
    );
    expect(restored.imagePaths, hasLength(1));
  });

  test('旧データも最初の投稿画像を代表画像として引き継ぐ', () {
    final json = SourcePost(
      title: '旧データ',
      imagePaths: const ['/support/legacy.jpg'],
    ).toJson()
      ..remove('thumbnailPath');

    final restored = SourcePost.fromJson(json);

    expect(restored.displayThumbnailPath, '/support/legacy.jpg');
  });

  test('削除したマップはクラウド削除キューへ残る', () async {
    final hub = LocalRepositoryHub(InMemoryDataStore());
    await hub.load();
    final map = await hub.maps.create(PinMap(name: '削除予定'));
    await hub.maps.delete(map.id);
    expect(hub.snapshot.pendingCloudDeletes, contains('maps:${map.id}'));

    final restored = AppSnapshot.fromJson(hub.snapshot.toJson());
    expect(restored.pendingCloudDeletes, contains('maps:${map.id}'));
  });

  test('削除した旅行プランと地点はクラウド削除キューへ残る', () async {
    final place = await hub.places.create(Place(name: '旅行先'), mapIds: ['m1']);
    final plan = await hub.plans.create(TripPlan(title: '旅行'));
    final stop = await hub.plans.addStop(
      PlanStop(planId: plan.id, placeId: place.id),
    );
    await hub.plans.delete(plan.id);
    expect(hub.snapshot.pendingCloudDeletes, contains('plans:${plan.id}'));
    expect(hub.snapshot.pendingCloudDeletes, contains('plan_stops:${stop.id}'));
  });

  test('クラウド統合は端末だけのデータと個人メモを削除しない', () async {
    final local = await hub.places.create(
      Place(name: '同期前', userMemo: '秘密のメモ'),
      mapIds: ['m1'],
    );
    await hub.mergeCloudData(
      maps: [PinMap(id: 'remote-map', name: '共有マップ')],
      places: [Place(id: local.id, name: '同期後')],
      mapPlaces: [],
      mapMembers: [],
    );

    expect(
      hub.snapshot.maps.map((map) => map.id),
      containsAll(['m1', 'm2', 'remote-map']),
    );
    final merged = hub.snapshot.places.singleWhere(
      (place) => place.id == local.id,
    );
    expect(merged.name, '同期後');
    expect(merged.userMemo, '秘密のメモ');
  });
}
