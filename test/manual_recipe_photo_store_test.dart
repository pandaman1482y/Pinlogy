import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pinlogy/recipe/services/manual_recipe_photo_store.dart';
import 'package:pinlogy/recipe/data/recipe_sync_policy.dart';
import 'package:pinlogy/recipe/models/recipe_models.dart';

void main() {
  test('large photo is a JPEG within pixel and byte limits', () {
    final input = img.Image(width: 1200, height: 900);
    final random = Random(42);
    for (var y = 0; y < input.height; y++) {
      for (var x = 0; x < input.width; x++) {
        input.setPixelRgb(
          x,
          y,
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        );
      }
    }
    final bytes = compressManualRecipePhoto(
      Uint8List.fromList(img.encodeJpg(input, quality: 95)),
    );
    final output = img.decodeJpg(bytes)!;
    expect(output.width, lessThanOrEqualTo(800));
    expect(output.height, lessThanOrEqualTo(800));
    expect(bytes.length, lessThanOrEqualTo(200 * 1024));
    expect(output.width / output.height, closeTo(1200 / 900, 0.02));
  });
  test('portrait photos stay portrait and small photos are not enlarged', () {
    final input = img.Image(width: 60, height: 120);
    final bytes = compressManualRecipePhoto(
      Uint8List.fromList(img.encodePng(input)),
    );
    final output = img.decodeJpg(bytes)!;
    expect(output.width, 60);
    expect(output.height, 120);
  });
  test('invalid input is rejected', () {
    expect(
      () => compressManualRecipePhoto(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(
      () => compressManualRecipePhoto(Uint8List(0)),
      throwsFormatException,
    );
  });
  test('cleanup removes only owned drafts and keeps original files', () async {
    final root = await Directory.systemTemp.createTemp('manual_photo_test_');
    try {
      final store = ManualRecipePhotoStore(directoryProvider: () async => root);
      final original = File('${root.path}/original.jpg');
      await original.writeAsBytes([1, 2, 3]);
      await store.deleteOwned(original.path);
      expect(await original.exists(), isTrue);
      final input = img.Image(width: 32, height: 32);
      final path = await store.save(Uint8List.fromList(img.encodePng(input)));
      expect(await File(path).exists(), isTrue);
      await store.deleteOwned(path);
      expect(await File(path).exists(), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });
  test('user-selected and removed covers survive later analysis merge', () {
    final now = DateTime.utc(2026, 10, 15);
    final existing = Recipe(
      id: 'r',
      sourcePostId: 'p',
      title: '料理',
      coverImagePath: '/manual.jpg',
      userEditedFields: {'coverImagePath'},
      createdAt: now,
      updatedAt: now,
    );
    final incoming = Recipe(
      id: 'r',
      sourcePostId: 'p',
      title: '料理',
      coverImagePath: '/analysis.jpg',
      createdAt: now,
      updatedAt: now,
    );
    expect(
      mergeAnalyzedRecipe(
        existing: existing,
        incoming: incoming,
        saveAutomatically: true,
      ).coverImagePath,
      '/manual.jpg',
    );
    final removed = Recipe(
      id: 'r',
      sourcePostId: 'p',
      title: '料理',
      userEditedFields: {'coverImagePath'},
      createdAt: now,
      updatedAt: now,
    );
    expect(
      mergeAnalyzedRecipe(
        existing: removed,
        incoming: incoming,
        saveAutomatically: true,
      ).coverImagePath,
      isNull,
    );
  });
}
