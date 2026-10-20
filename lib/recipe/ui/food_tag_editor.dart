import 'package:flutter/material.dart';

List<String> splitFoodEntries(String value) => value
    .split(RegExp(r'[,，、\n\r;；]+'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toSet()
    .toList();

/// Explicit add/remove controls, while still saving any unsubmitted draft.
class FoodTagEditor extends StatelessWidget {
  const FoodTagEditor({
    super.key,
    required this.controller,
    required this.values,
    required this.label,
    required this.fieldKey,
    required this.onChanged,
  });
  final TextEditingController controller;
  final List<String> values;
  final String label;
  final String fieldKey;
  final ValueChanged<List<String>> onChanged;

  void _add() {
    final entries = splitFoodEntries(controller.text);
    if (entries.isEmpty) return;
    onChanged({...values, ...entries}.toList());
    controller.clear();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: ValueKey(fieldKey),
        controller: controller,
        minLines: 1,
        maxLines: 3,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _add(),
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        decoration: InputDecoration(
          labelText: label,
          hintText: '食材名を入力して追加',
          helperText: '複数登録できます。読点・カンマ・改行でも区切れます。',
          helperMaxLines: 2,
          suffixIcon: IconButton(
            key: ValueKey('${fieldKey}_add'),
            tooltip: '$labelを追加',
            onPressed: _add,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ),
      ),
      if (values.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final value in values)
              InputChip(
                label: Text(value),
                onDeleted: () =>
                    onChanged(values.where((item) => item != value).toList()),
              ),
          ],
        ),
      ],
    ],
  );
}
