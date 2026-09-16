import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/app/app.dart';
import 'package:pinlogy/app/app_scope.dart';
import 'package:pinlogy/app/pinlogy_controller.dart';
import 'package:pinlogy/recipe/data/recipe_store.dart';
import 'package:pinlogy/recipe/recipe_controller.dart';
import 'package:pinlogy/recipe/recipe_scope.dart';
import 'package:pinlogy/repositories/local_data_store.dart';
import 'package:pinlogy/services/device_location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpAt(
  WidgetTester tester, {
  required Size size,
  required double textScale,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  SharedPreferences.setMockInitialValues({
    'ai_post_analysis_consent_decided_v1': true,
    'ai_post_analysis_consent_v1': true,
  });
  final legacy = PinlogyController(
    store: InMemoryDataStore(),
    deviceLocationService: MockDeviceLocationService(),
    seedIfEmpty: false,
    enablePlatformShare: false,
  );
  await legacy.initialize();
  final recipes = RecipeController(legacy: legacy, store: MemoryRecipeStore());
  await recipes.initialize();
  await tester.pumpWidget(
    AppScope(
      controller: legacy,
      child: RecipeScope(controller: recipes, child: const PinlogyApp()),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(recipes.dispose);
  addTearDown(legacy.dispose);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('小型Android相当でも4タブが崩れない', (tester) async {
    await pumpAt(tester, size: const Size(320, 568), textScale: 1);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('検索'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('文字サイズ160%でも主要画面が開く', (tester) async {
    await pumpAt(tester, size: const Size(412, 915), textScale: 1.6);
    await tester.tap(find.text('マイページ'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
