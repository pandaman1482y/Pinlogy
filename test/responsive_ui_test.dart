import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/app/app.dart';
import 'package:pinlogy/app/app_scope.dart';
import 'package:pinlogy/app/pinlogy_controller.dart';
import 'package:pinlogy/repositories/local_data_store.dart';
import 'package:pinlogy/services/device_location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<PinlogyController> _pumpResponsiveApp(
  WidgetTester tester, {
  required Size logicalSize,
  required double textScale,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = logicalSize;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  SharedPreferences.setMockInitialValues({
    'pinlogy_onboarding_v1_completed': true,
    'ai_post_analysis_consent_decided_v1': true,
    'ai_post_analysis_consent_v1': false,
  });
  final controller = PinlogyController(
    store: InMemoryDataStore(),
    deviceLocationService: MockDeviceLocationService(),
    enablePlatformShare: false,
  );
  await controller.initialize();
  await tester.pumpWidget(
    AppScope(controller: controller, child: const PinlogyApp()),
  );
  await tester.pumpAndSettle();
  addTearDown(controller.dispose);
  return controller;
}

Future<void> _openMainTabsWithoutLayoutErrors(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.tap(find.text('受信箱'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await tester.tap(find.text('マイページ'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('小型Android相当でも主要タブが崩れない', (tester) async {
    await _pumpResponsiveApp(
      tester,
      logicalSize: const Size(320, 568),
      textScale: 1,
    );
    await _openMainTabsWithoutLayoutErrors(tester);
  });

  testWidgets('文字サイズ160%でも主要タブが崩れない', (tester) async {
    await _pumpResponsiveApp(
      tester,
      logicalSize: const Size(412, 915),
      textScale: 1.6,
    );
    await _openMainTabsWithoutLayoutErrors(tester);
  });
}
