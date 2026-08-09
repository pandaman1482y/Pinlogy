import 'package:flutter/material.dart';

import '../core/errors.dart';

void showErrorSnackBar(BuildContext context, Object error) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(toUserMessage(error)),
        backgroundColor: const Color(0xFF5C2E2E),
        behavior: SnackBarBehavior.floating,
      ),
    );
}

void showInfoSnackBar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
}

/// 失敗時にエラーSnackBarを出し、成功時のみ結果を返す。
Future<T?> runGuarded<T>(
  BuildContext context,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } catch (error) {
    if (context.mounted) showErrorSnackBar(context, error);
    return null;
  }
}

/// void 操作向け。成功なら true。
Future<bool> runGuardedAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } catch (error) {
    if (context.mounted) showErrorSnackBar(context, error);
    return false;
  }
}
