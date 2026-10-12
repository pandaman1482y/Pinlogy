import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_scope.dart';
import 'app/pinlogy_controller.dart';
import 'recipe/recipe_controller.dart';
import 'recipe/recipe_scope.dart';
import 'services/notification_service.dart';
import 'services/billing_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = PinlogyController(seedIfEmpty: false);
  final recipeController = RecipeController(legacy: controller);
  runApp(
    AppScope(
      controller: controller,
      child: RecipeScope(
        controller: recipeController,
        child: const PinlogyApp(),
      ),
    ),
  );
  // ネットワークサービスの初期化を最初のFlutterフレームより先に待たない。
  // 端末内スナップショットを先に表示し、通知・課金・クラウド同期は
  // 起動後に合流させる。
  unawaited(_bootstrap(controller, recipeController));
}

Future<void> _bootstrap(
  PinlogyController controller,
  RecipeController recipeController,
) async {
  try {
    unawaited(PinlogyNotificationService.instance.initialize());
    await controller.initialize();
    await recipeController.initialize();
    // 復元済みのSupabaseユーザーをRevenueCatの初期App User IDに使用する。
    await BillingService.instance.initialize();
  } catch (error, stackTrace) {
    // 起動後サービスの失敗でFlutterツリーを終了させない。
    debugPrint('app_background_bootstrap_failed $error');
    debugPrintStack(
      label: 'app_background_bootstrap_failed',
      stackTrace: stackTrace,
    );
  }
}
