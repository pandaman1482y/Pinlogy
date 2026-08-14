import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/services/post_category_service.dart';

void main() {
  test('メモから複数カテゴリを重複なく提案できる', () {
    final categories = suggestPostCategories('八尾の珈琲とケーキがおいしいカフェ');
    expect(categories, containsAll(['カフェ', 'スイーツ']));
  });

  test('カテゴリ語がないメモでは未分類値を作らない', () {
    expect(suggestPostCategories('また今度行きたい'), isEmpty);
  });
}
