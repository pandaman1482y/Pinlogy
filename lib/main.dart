import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_scope.dart';
import 'app/pinlogy_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = PinlogyController(seedIfEmpty: false);
  await controller.initialize();
  runApp(AppScope(controller: controller, child: const PinlogyApp()));
}
