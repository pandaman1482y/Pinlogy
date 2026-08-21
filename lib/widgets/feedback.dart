import 'package:flutter/material.dart';

import '../core/errors.dart';

void showErrorSnackBar(BuildContext context, Object error) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final message = toUserMessage(error);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
        backgroundColor: const Color(0xFF5C2E2E),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '全文を見る',
          textColor: Colors.white,
          onPressed: () {
            if (!context.mounted) return;
            showMessageDetails(context, title: 'エラー内容', message: message);
          },
        ),
      ),
    );
}

Future<void> showMessageDetails(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SelectableText(message),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('閉じる'),
        ),
      ],
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
