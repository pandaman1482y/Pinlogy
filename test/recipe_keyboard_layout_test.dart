import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/recipe/ui/recipe_editor_page.dart';

void main() {
  testWidgets('photo area remains tappable without the overlay label', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: RecipeEditorPage()));
    expect(find.text('タップして写真を追加'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('manual_photo_area')));
    await tester.pumpAndSettle();
    expect(find.text('写真から選ぶ'), findsOneWidget);
    Navigator.of(tester.element(find.text('写真から選ぶ'))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final label in ['料理名', '説明・メモ']) {
    testWidgets('$label stays above the keyboard', (tester) async {
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(const MaterialApp(home: RecipeEditorPage()));
      final field = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
      await tester.scrollUntilVisible(
        field,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(tester.element(field), alignment: 0.15);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).focusNode?.hasFocus, isTrue);
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      final keyboardTop =
          (tester.view.physicalSize.height - tester.view.viewInsets.bottom) /
          tester.view.devicePixelRatio;
      expect(tester.getRect(field).bottom, lessThanOrEqualTo(keyboardTop));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
