import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_scope.dart';
import 'app/pinlogy_controller.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PinlogyNotificationService.instance.initialize();
  final controller = PinlogyController(seedIfEmpty: false);
  await controller.initialize();
  runApp(AppScope(controller: controller, child: const PinlogyApp()));
}
