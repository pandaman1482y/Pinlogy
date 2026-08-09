import 'dart:math' as math;

import 'package:flutter/material.dart';

/// キーボード分を差し引いたボトムシート本体の高さ。
double modalSheetHeight(
  BuildContext context, {
  double fraction = 0.72,
  double minHeight = 280,
}) {
  final media = MediaQuery.of(context);
  final available = media.size.height - media.viewInsets.bottom;
  return math.max(minHeight, available * fraction);
}

/// ダイアログ退場アニメ後に TextEditingController を破棄する。
void disposeAfterFrame(List<TextEditingController> controllers) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    for (final c in controllers) {
      c.dispose();
    }
  });
}
