import 'package:flutter/material.dart';

import 'pinlogy_controller.dart';

class AppScope extends InheritedNotifier<PinlogyController> {
  const AppScope({
    super.key,
    required PinlogyController controller,
    required super.child,
  }) : super(notifier: controller);

  static PinlogyController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope が見つかりません');
    return scope!.notifier!;
  }

  static PinlogyController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope が見つかりません');
    return scope!.notifier!;
  }
}
