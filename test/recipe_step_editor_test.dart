import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/recipe/models/recipe_models.dart';
import 'package:pinlogy/recipe/ui/recipe_editor_page.dart';

void main() {
  test('new step headings persist and old records still load', () {
    final step = RecipeStep(
      id: 's',
      order: 1,
      title: '材料を切る',
      instruction: '鶏肉を切る',
    );
    final loaded = RecipeStep.fromJson(step.toJson());
    expect(loaded.title, step.title);
    expect(loaded.instruction, step.instruction);
    expect(
      RecipeStep.fromJson({'order': 1, 'instruction': '混ぜる'}).title,
      isNull,
    );
  });
  test(
    'editing and renumbering keep timing, evidence and cooking metadata',
    () {
      final step = RecipeStep(
        id: 's',
        order: 2,
        instruction: '混ぜる',
        durationSeconds: 60,
        imageIndex: 3,
        ingredientIndexes: [0, 1],
        preparedItems: ['たれ'],
        tools: ['ボウル'],
        tips: ['軽く混ぜる'],
        evidenceId: 'e',
        confidencePercent: 90,
      );
      final edited = step.copyWith(
        order: 1,
        title: '仕上げ',
        instruction: '盛り付ける',
        userEdited: true,
      );
      expect(edited.id, step.id);
      expect(edited.order, 1);
      expect(edited.tools, step.tools);
      expect(edited.tips, step.tips);
      expect(edited.preparedItems, step.preparedItems);
      expect(edited.durationSeconds, 60);
      expect(edited.imageIndex, 3);
      expect(edited.evidenceId, 'e');
      expect(edited.ingredientIndexes, [0, 1]);
    },
  );
  testWidgets('dialog validates body then returns heading and edited content', (
    tester,
  ) async {
    RecipeStep? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showRecipeStepEditor(context, order: 1);
              },
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();
    expect(find.text('作り方を入力してください'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('step_title')), '材料を切る');
    await tester.enterText(
      find.byKey(const ValueKey('step_instruction')),
      '鶏肉を一口大に切る。',
    );
    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();
    expect(result?.title, '材料を切る');
    expect(result?.instruction, '鶏肉を一口大に切る。');
    expect(tester.takeException(), isNull);
  });
  testWidgets('cancel leaves the existing step unchanged', (tester) async {
    final original = RecipeStep(
      id: 's',
      order: 1,
      title: '元の見出し',
      instruction: '元の作り方',
    );
    RecipeStep? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showRecipeStepEditor(
                  context,
                  order: 1,
                  original: original,
                );
              },
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('step_instruction')),
      '変更',
    );
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(original.instruction, '元の作り方');
    expect(tester.takeException(), isNull);
  });
}
