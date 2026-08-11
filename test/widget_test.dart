import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/app/app.dart';
import 'package:pinlogy/app/app_scope.dart';
import 'package:pinlogy/app/pinlogy_controller.dart';
import 'package:pinlogy/features/maps/maps_tab.dart';
import 'package:pinlogy/models/models.dart';
import 'package:pinlogy/repositories/local_data_store.dart';
import 'package:pinlogy/services/device_location_service.dart';
import 'package:pinlogy/services/location_services.dart';
import 'package:pinlogy/services/share_receiver_service.dart';
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
    expect(find.text('ごはん屋'), findsOneWidget);
    expect(find.text('北海道旅行'), findsOneWidget);
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
