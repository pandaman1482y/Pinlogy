import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/recipe/data/import_thumbnail.dart';
import 'package:pinlogy/recipe/ui/recipe_widgets.dart';
import 'package:pinlogy/recipe/ui/recipe_editor_page.dart';

void main() {
  test('newly acquired thumbnail replaces an older import image', () {
    expect(
      resolveImportThumbnail(
        postThumbnail: 'https://example.com/new.jpg',
        importThumbnail: '/old.jpg',
        savedThumbnail: '/saved.jpg',
      ),
      'https://example.com/new.jpg',
    );
  });
  test('placeholders fall back to acquired or saved images', () {
    expect(
      resolveImportThumbnail(
        postThumbnail: 'local://placeholder',
        importThumbnail: '/existing.jpg',
      ),
      '/existing.jpg',
    );
    expect(
      resolveImportThumbnail(
        importThumbnail: 'local://placeholder',
        savedThumbnail: '/saved.jpg',
      ),
      '/saved.jpg',
    );
    expect(resolveImportThumbnail(postThumbnail: '  '), isNull);
  });
  test('unmaterialized cloud references do not hide a usable local cover', () {
    expect(
      resolveImportThumbnail(
        importThumbnail: 'recipe-media://owner/photo.jpg',
        savedThumbnail: '/saved.jpg',
      ),
      '/saved.jpg',
    );
  });
  testWidgets('long tool labels wrap without overflowing on a narrow screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 220,
              child: RecipeIconText(
                icon: Icons.kitchen_outlined,
                label: '使う道具',
                text: '落とし蓋、フライパン、長い名前の調理道具、盛り付け用の大きなお皿',
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final rich = tester.widget<Text>(find.byType(Text).last);
    expect(rich.style?.fontWeight, FontWeight.normal);
    expect(rich.style?.fontSize, 14);
  });
  testWidgets(
    'manual memo uses the same automatic floating label behavior as the title',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RecipeEditorPage()));
      final finder = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '説明・メモ',
      );
      await tester.scrollUntilVisible(
        finder,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      final field = tester.widget<TextField>(finder);
      expect(
        field.decoration?.floatingLabelBehavior,
        FloatingLabelBehavior.auto,
      );
      expect(field.textAlignVertical, TextAlignVertical.top);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('tapping the photo area opens photo selection', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RecipeEditorPage()));
    await tester.tap(find.byKey(const ValueKey('manual_photo_area')));
    await tester.pumpAndSettle();
    expect(find.text('写真から選ぶ'), findsOneWidget);
    expect(find.text('カメラで撮る'), findsOneWidget);
    Navigator.of(tester.element(find.text('写真から選ぶ'))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
