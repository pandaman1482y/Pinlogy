import 'dart:math' as math;

import 'package:flutter/material.dart';

/// キーボード分を差し引いたボトムシート本体の高さ。
double modalSheetHeight(
  BuildContext context, {
  double fraction = 0.72,
  double minHeight = 280,
}) {
  final media = MediaQuery.of(context);
  final available = math.max(0.0, media.size.height - media.viewInsets.bottom);
  final preferred = math.max(minHeight, available * fraction);

  // キーボード表示中は最低高よりも、実際に見えている領域を優先する。
  // ここで空き領域を超える高さを返すと、ボトムシート下部がキーボードに
  // 隠れて操作できなくなる。
  return math.min(available, preferred);
}

/// ダイアログ退場アニメ後に TextEditingController を破棄する。
void disposeAfterFrame(List<TextEditingController> controllers) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    for (final c in controllers) {
      c.dispose();
    }
  });
}
