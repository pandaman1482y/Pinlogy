import 'package:flutter/material.dart';

import '../services/post_category_service.dart';

Future<List<String>?> showPostCategoryEditor(
  BuildContext context, {
  required Iterable<String> initialCategories,
}) async {
  final selected = initialCategories
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty && value != 'その他')
      .toSet();
  final controller = TextEditingController();
  try {
    return await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void addCategory() {
            final value = controller.text.trim();
            if (value.isEmpty || value == 'その他') return;
            setDialogState(() {
              selected.add(value);
              controller.clear();
            });
          }

          final custom = selected
              .where((value) => !standardPostCategories.contains(value))
              .toList()
            ..sort();
          return AlertDialog(
            scrollable: true,
            title: const Text('カテゴリを編集'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('この投稿に当てはまるカテゴリを選択してください。'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final value in standardPostCategories)
                      FilterChip(
                        label: Text(value),
                        selected: selected.contains(value),
                        onSelected: (enabled) => setDialogState(() {
                          if (enabled) {
                            selected.add(value);
                          } else {
                            selected.remove(value);
                          }
                        }),
                      ),
                  ],
                ),
                if (custom.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final value in custom)
                        InputChip(
                          label: Text(value),
                          onDeleted: () =>
                              setDialogState(() => selected.remove(value)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'カテゴリを追加',
                    hintText: '例：うどん、デート',
                    suffixIcon: IconButton(
                      tooltip: '追加',
                      onPressed: addCategory,
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ),
                  onSubmitted: (_) => addCategory(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () {
                  final result = selected.toList()..sort();
                  Navigator.pop(dialogContext, result);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    controller.dispose();
  }
}
