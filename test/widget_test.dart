import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/app/app.dart';
import 'package:pinlogy/app/app_scope.dart';
import 'package:pinlogy/app/pinlogy_controller.dart';
import 'package:pinlogy/features/maps/maps_tab.dart';
import 'package:pinlogy/features/plans/plan_detail_page.dart';
import 'package:pinlogy/models/models.dart';
import 'package:pinlogy/repositories/local_data_store.dart';
import 'package:pinlogy/services/device_location_service.dart';
import 'package:pinlogy/services/location_services.dart';
import 'package:pinlogy/services/share_receiver_service.dart';
import 'package:pinlogy/widgets/sheet_layout.dart';
import 'package:pinlogy/widgets/place_map_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FailingAnalysisService implements PostAnalysisService {
  @override
  Future<PostAnalysisResponse> analyze(PostAnalysisRequest request) async {
    throw StateError('SocketException: Failed host lookup');
  }
}

Future<PinlogyController> pumpApp(
  WidgetTester tester, {
  PostAnalysisService? analysisService,
  bool seedIfEmpty = true,
}) async {
  SharedPreferences.setMockInitialValues({
    'pinlogy_onboarding_v1_completed': true,
    'ai_post_analysis_consent_decided_v1': true,
    'ai_post_analysis_consent_v1': false,
  });
  final controller = PinlogyController(
    store: InMemoryDataStore(),
    analysisService: analysisService ?? MockPostAnalysisService(),
    deviceLocationService: MockDeviceLocationService(),
    seedIfEmpty: seedIfEmpty,
    enablePlatformShare: false,
  );
  await controller.initialize();
  await tester.pumpWidget(
    AppScope(controller: controller, child: const PinlogyApp()),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('アプリが起動しマップ一覧が表示される', (tester) async {
    await pumpApp(tester);
    expect(find.text('Pinlogy'), findsOneWidget);
    expect(find.text('SNSから追加'), findsOneWidget);
    expect(find.text('手動で追加'), findsOneWidget);
    expect(find.text('ごはん屋'), findsOneWidget);
    expect(find.text('北海道旅行'), findsOneWidget);
  });

  testWidgets('無料プランで使える機能が確認できる', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('マイページ'));
    await tester.pumpAndSettle();
    expect(find.text('無料プラン'), findsOneWidget);
    expect(find.textContaining('手動追加'), findsOneWidget);
    expect(find.textContaining('AI取り込みは1日10回'), findsOneWidget);
  });

  testWidgets('狭い画面では追加方法が縦並びになり表示が崩れない', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpApp(tester);
    final snsPosition = tester.getTopLeft(find.text('SNSから追加'));
    final manualPosition = tester.getTopLeft(find.text('手動で追加'));

    expect(manualPosition.dy, greaterThan(snsPosition.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('手動追加画面は最初からキーボードを開かない', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('手動で追加'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == '店名・住所',
      ),
    );
    expect(field.autofocus, isFalse);
    expect(find.text('メモなしでも場所を検索します。'), findsNothing);
  });

  testWidgets('キーボード表示中のシート高が表示領域を超えない', (tester) async {
    double? height;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            viewInsets: EdgeInsets.only(bottom: 500),
          ),
          child: Builder(
            builder: (context) {
              height = modalSheetHeight(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(height, lessThanOrEqualTo(344));
  });

  test('AI解析の場所カテゴリと料理ジャンルを読み込める', () {
    final response = PostAnalysisResponse.fromJson({
      'source_post_id': 'post-1',
      'candidates': [
        {
          'name': 'テストラーメン',
          'category': '飲食店',
          'genres': ['ラーメン'],
        },
      ],
    });

    expect(response.candidates.single.category, '飲食店');
    expect(response.candidates.single.genres, ['ラーメン']);
  });

  testWidgets('AI解析のカテゴリと料理ジャンルを場所へ保存できる', (tester) async {
    final controller = await pumpApp(tester);
    final map = controller.hub.snapshot.maps.first;
    final places = await controller.addCandidatesToMap(
      candidates: [
        ExtractionCandidate(
          name: 'カテゴリーテスト店',
          address: '大阪府大阪市',
          category: '飲食店',
          genres: const ['焼肉', '韓国料理'],
        ),
      ],
      mapId: map.id,
      sourcePostId: 'post-kyoto-5',
    );
    final tags = await controller.tags.tagsForPlace(places.single.id);

    expect(places.single.category, '飲食店');
    expect(tags.map((tag) => tag.name), containsAll(['焼肉', '韓国料理']));
  });

  testWidgets('マップを作成できる', (tester) async {
    final controller = await pumpApp(tester);
    await tester.tap(find.byTooltip('マップを追加'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == '例：京都旅行、行きたいごはん屋',
      ),
      'テストマップ',
    );
    await tester.tap(find.text('作成する'));
    await tester.pumpAndSettle();
    expect(controller.hub.snapshot.maps.any((m) => m.name == 'テストマップ'), isTrue);
    expect(find.text('テストマップ'), findsOneWidget);
  });

  testWidgets('マップを編集・削除できる', (tester) async {
    final controller = await pumpApp(tester);
    final target = controller.hub.snapshot.maps.first;
    await controller.maps.update(target.copyWith(name: '編集後マップ'));
    await tester.pumpAndSettle();
    expect(find.text('編集後マップ'), findsOneWidget);

    await controller.maps.delete(target.id);
    await tester.pumpAndSettle();
    expect(find.text('編集後マップ'), findsNothing);
  });

  testWidgets('場所を追加し複数マップへ関連付けできる', (tester) async {
    final controller = await pumpApp(tester);
    final maps = controller.hub.snapshot.maps;
    final place = await controller.places.create(
      Place(name: '新規カフェ', address: '東京都渋谷区', saveReason: 'テスト'),
      mapIds: [maps[0].id],
    );
    await controller.places.addToMap(placeId: place.id, mapId: maps[1].id);
    final linked = await controller.places.mapsForPlace(place.id);
    expect(linked.map((m) => m.id), containsAll([maps[0].id, maps[1].id]));
    expect(
      controller.hub.snapshot.places.where((p) => p.name == '新規カフェ').length,
      1,
    );
  });

  testWidgets('場所詳細を開ける', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('マイページ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存した場所'));
    await tester.pumpAndSettle();
    expect(find.text('保存済み'), findsOneWidget);
    await tester.tap(find.byType(PlaceListTile).first);
    await tester.pumpAndSettle();
    expect(find.text('経路'), findsOneWidget);
    expect(find.text('共有'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('保存した理由'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('保存した理由'), findsOneWidget);
  });

  testWidgets('訪問回数を更新できる', (tester) async {
    final controller = await pumpApp(tester);
    final place = controller.hub.snapshot.places.first;
    final before = place.visitCount;
    final updated = await controller.visits.markVisited(place.id);
    expect(updated.visitCount, before + 1);
    expect(updated.isVisited, isTrue);
  });

  testWidgets('検索・絞り込みが動作する', (tester) async {
    final controller = await pumpApp(tester);
    final hits = await controller.places.search(query: 'ソワレ');
    expect(hits, isNotEmpty);
    expect(hits.first.name, contains('ソワレ'));

    final unvisited = await controller.places.search(
      filter: PlaceFilterOption.unvisited,
    );
    expect(unvisited.every((p) => !p.isVisited), isTrue);
  });

  testWidgets('投稿から複数候補を選択できる', (tester) async {
    final controller = await pumpApp(tester);
    await tester.tap(find.text('受信箱'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('喫茶ソワレ').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('件見つかりました'), findsOneWidget);
    expect(find.text('喫茶ソワレ'), findsWidgets);
    expect(find.text('全選択'), findsOneWidget);

    final before = controller.hub.snapshot.places.length;
    await tester.tap(find.textContaining('件を追加'));
    await tester.pumpAndSettle();
    expect(controller.hub.snapshot.places.length >= before, isTrue);
  });

  testWidgets('住所不一致確認が表示される', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('受信箱'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('喫茶ソワレ').first);
    await tester.pumpAndSettle();
    final searchButton = find.text('店名・住所で正しい場所を検索').first;
    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.tap(searchButton);
    await tester.pumpAndSettle();
    expect(find.text('正しい場所を検索'), findsOneWidget);
    expect(find.textContaining('TikTokの画面に表示された店名'), findsOneWidget);
  });

  test('ローカル保存後に再読み込みできる', () async {
    SharedPreferences.setMockInitialValues({
      'pinlogy_onboarding_v1_completed': true,
      'ai_post_analysis_consent_decided_v1': true,
      'ai_post_analysis_consent_v1': false,
    });
    final store = SharedPreferencesStore(prefsKey: 'test_pinlogy');
    final first = PinlogyController(
      store: store,
      seedIfEmpty: true,
      enablePlatformShare: false,
    );
    await first.initialize();
    await first.createMap(name: '永続化マップ');
    final second = PinlogyController(
      store: store,
      seedIfEmpty: false,
      enablePlatformShare: false,
    );
    await second.initialize();
    expect(second.hub.snapshot.maps.any((m) => m.name == '永続化マップ'), isTrue);
  });

  test('連続共有を順番どおり保留できる', () async {
    SharedPreferences.setMockInitialValues({
      'pinlogy_onboarding_v1_completed': true,
      'ai_post_analysis_consent_decided_v1': true,
      'ai_post_analysis_consent_v1': false,
    });
    final controller = PinlogyController(
      store: InMemoryDataStore(),
      analysisService: MockPostAnalysisService(),
      seedIfEmpty: false,
      enablePlatformShare: false,
    );
    await controller.initialize();
    await controller.shareIntake.ingest(
      const SharedContent(title: '1件目', text: '最初の共有'),
    );
    await controller.shareIntake.ingest(
      const SharedContent(title: '2件目', text: '次の共有'),
    );
    await Future<void>.delayed(Duration.zero);

    final pending = controller.consumePendingSharedPosts();
    expect(pending.map((post) => post.title), ['1件目', '2件目']);
    expect(controller.consumePendingSharedPosts(), isEmpty);
    controller.dispose();
  });

  testWidgets('API失敗時も元投稿が受信箱に残る', (tester) async {
    final controller = await pumpApp(
      tester,
      analysisService: FailingAnalysisService(),
      seedIfEmpty: false,
    );
    await controller.createMap(name: '空マップ');
    await controller.shareReceiver.receive(
      const SharedContent(
        url: 'https://www.instagram.com/p/fail-case',
        text: '失敗テスト',
        title: '失敗する投稿',
      ),
      waitForAnalysis: true,
    );
    await tester.pumpAndSettle();
    expect(
      controller.hub.snapshot.sourcePosts.any((p) => p.title == '失敗する投稿'),
      isTrue,
    );
    final job = controller.jobForPost(
      controller.hub.snapshot.sourcePosts
          .firstWhere((p) => p.title == '失敗する投稿')
          .id,
    );
    expect(job?.status, AnalysisJobStatus.failed);
    expect(job?.errorMessage, contains('ネットワーク'));
  });

  testWidgets('プランタブは初期が空でつくれる', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('マイページ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旅行プラン'));
    await tester.pumpAndSettle();
    expect(find.text('まだプランがない'), findsOneWidget);

    await tester.tap(find.text('プランをつくる'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('つくる'));
    await tester.pumpAndSettle();
    expect(find.text('無題のプラン'), findsOneWidget);
    expect(find.text('まだ行程がない'), findsOneWidget);
  });

  testWidgets('場所追加後にプランマップを生成できる', (tester) async {
    final controller = await pumpApp(tester);
    final plan = await controller.plans.create(TripPlan(title: '大阪旅行'));
    final places = controller.hub.snapshot.places.take(2).toList();
    for (var i = 0; i < places.length; i++) {
      await controller.plans.addStop(
        PlanStop(
          planId: plan.id,
          placeId: places[i].id,
          sortOrder: i,
        ),
      );
    }

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(home: PlanDetailPage(planId: plan.id)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('プランマップ'), findsOneWidget);

    await tester.tap(find.text('プランマップ'));
    await tester.pumpAndSettle();
    expect(find.text('大阪旅行の地図'), findsOneWidget);
    expect(find.byType(PlaceMapView), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  test('プランの開始時刻を保存・復元できる', () {
    final plan = TripPlan(title: '朝のプラン', startTimeMinutes: 8 * 60 + 30);
    final restored = TripPlan.fromJson(plan.toJson());

    expect(restored.startTimeMinutes, 510);
  });

  test('区間の余裕・予約・到着期限を保存・復元できる', () {
    final stop = PlanStop(
      planId: 'plan-1',
      placeId: 'place-1',
      transitToNext: TransitMode.taxi,
      transitMinutes: 25,
      transitTimeIsManual: true,
      transitBufferMinutes: 15,
      reservationTimeMinutes: 12 * 60,
      arrivalDeadlineMinutes: 11 * 60 + 50,
    );
    final restored = PlanStop.fromJson(stop.toJson());

    expect(restored.transitToNext, TransitMode.taxi);
    expect(restored.transitMinutes, 25);
    expect(restored.transitTimeIsManual, isTrue);
    expect(restored.transitBufferMinutes, 15);
    expect(restored.reservationTimeMinutes, 720);
    expect(restored.arrivalDeadlineMinutes, 710);
  });

  testWidgets('マップを複製し旅行日程を自動作成できる', (tester) async {
    final controller = await pumpApp(tester);
    final source = controller.hub.snapshot.maps.first;
    final sourceCount = controller.placeCountForMap(source.id);

    final copy = await controller.duplicateMap(source.id);
    expect(copy.isPublic, isFalse);
    expect(copy.allowsCollaboration, isFalse);
    expect(controller.placeCountForMap(copy.id), sourceCount);
    final sourcePlaces = await controller.places.getByMapId(source.id);
    final copiedPlaces = await controller.places.getByMapId(copy.id);
    expect(
      copiedPlaces
          .map((place) => place.id)
          .toSet()
          .intersection(sourcePlaces.map((place) => place.id).toSet()),
      isEmpty,
    );

    final plan = await controller.createAutoPlanFromMap(source.id);
    final stops = await controller.plans.stopsForPlan(plan.id);
    expect(stops.length, sourceCount);
    expect(stops.every((stop) => stop.dayDate != null), isTrue);
  });
}
