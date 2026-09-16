import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_scope.dart';
import 'app/pinlogy_controller.dart';
import 'recipe/recipe_controller.dart';
import 'recipe/recipe_scope.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PinlogyNotificationService.instance.initialize();
  final controller = PinlogyController(seedIfEmpty: false);
  await controller.initialize();
  final recipeController = RecipeController(legacy: controller);
  await recipeController.initialize();
  runApp(
    AppScope(
      controller: controller,
      child: RecipeScope(
        controller: recipeController,
        child: const PinlogyApp(),
      ),
    ),
  );
}
