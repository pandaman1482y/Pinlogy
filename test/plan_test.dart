import 'package:flutter_test/flutter_test.dart';

import 'package:pinlogy/models/models.dart';
import 'package:pinlogy/repositories/local_data_store.dart';
import 'package:pinlogy/repositories/local_repositories.dart';

void main() {
  test('初期シードにプランは含まれない', () async {
    final hub = LocalRepositoryHub(InMemoryDataStore());
    await hub.load(seedIfEmpty: true);
    expect(hub.snapshot.plans, isEmpty);
    expect(hub.snapshot.planStops, isEmpty);
  });

  test('null のタイトル・開始日・日付なし地点を受け入れられる', () async {
    final hub = LocalRepositoryHub(InMemoryDataStore());
    await hub.load(seedIfEmpty: true);

    final plan = await hub.plans.create(TripPlan());
    expect(plan.title, '無題のプラン');
    expect(plan.startDate, isNull);
    expect(plan.notes, isEmpty);

    final place = hub.snapshot.places.first;
    final stop = await hub.plans.addStop(
      PlanStop(planId: plan.id, placeId: place.id),
    );
    expect(stop.dayDate, isNull);
    expect(stop.stayMinutes, isNull);
    expect(stop.transitToNext, isNull);
  });

  test('プランに日付つき行程と移動・滞在時間を保存できる', () async {
    final hub = LocalRepositoryHub(InMemoryDataStore());
    await hub.load(seedIfEmpty: true);

    final plan = await hub.plans.create(
      TripPlan(title: 'テスト行程', startDate: DateTime(2026, 9, 1)),
    );
    final places = hub.snapshot.places;
    expect(places.length, greaterThanOrEqualTo(2));

    final first = await hub.plans.addStop(
      PlanStop(
        planId: plan.id,
        placeId: places[0].id,
        dayDate: DateTime(2026, 9, 1),
        stayMinutes: 50,
        transitToNext: TransitMode.walk,
        transitMinutes: 10,
      ),
    );
    await hub.plans.addStop(
      PlanStop(
        planId: plan.id,
        placeId: places[1].id,
        dayDate: DateTime(2026, 9, 1),
        stayMinutes: 40,
      ),
    );

    final stops = await hub.plans.stopsForPlan(plan.id);
    expect(stops.length, 2);
    expect(stops.first.id, first.id);
    expect(stops.first.transitToNext, TransitMode.walk);
    expect(stops.first.transitMinutes, 10);
    expect(stops.last.sortOrder, 1);

    await hub.plans.reorderStops(
      planId: plan.id,
      dayDate: DateTime(2026, 9, 1),
      orderedStopIds: [stops.last.id, stops.first.id],
    );
    final reordered = await hub.plans.stopsForPlan(plan.id);
    expect(reordered.first.placeId, places[1].id);
    expect(reordered.last.placeId, places[0].id);
  });

  test('プラン削除で地点も消える', () async {
    final hub = LocalRepositoryHub(InMemoryDataStore());
    await hub.load(seedIfEmpty: true);
    final plan = await hub.plans.create(TripPlan(title: '削除テスト'));
    await hub.plans.addStop(
      PlanStop(
        planId: plan.id,
        placeId: hub.snapshot.places.first.id,
        dayDate: DateTime(2026, 9, 1),
      ),
    );
    expect(
      hub.snapshot.planStops.where((s) => s.planId == plan.id),
      isNotEmpty,
    );

    await hub.plans.delete(plan.id);
    expect(hub.snapshot.plans.where((p) => p.id == plan.id), isEmpty);
    expect(hub.snapshot.planStops.where((s) => s.planId == plan.id), isEmpty);
  });

  test('壊れたプランJSONは読み飛ばせる', () {
    final snapshot = AppSnapshot.fromJson({
      'plans': [
        null,
        {'title': null, 'startDate': null},
      ],
      'planStops': [
        null,
        {'planId': null, 'placeId': 'x'},
        {'planId': 'p1', 'placeId': 'place-1', 'dayDate': null},
      ],
    });
    expect(snapshot.plans.length, 1);
    expect(snapshot.plans.first.title, '無題のプラン');
    expect(snapshot.plans.first.startDate, isNull);
    expect(snapshot.planStops.length, 1);
    expect(snapshot.planStops.first.dayDate, isNull);
  });
}
