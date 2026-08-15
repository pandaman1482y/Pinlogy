import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/services/source_media_store.dart';

void main() {
  test('端末に残っている代表画像だけを利用可能と判定する', () async {
    final directory = await Directory.systemTemp.createTemp('pinlogy-media-');
    addTearDown(() => directory.delete(recursive: true));
    final image = File('${directory.path}/thumbnail.jpg');
    await image.writeAsBytes(const [0xff, 0xd8, 0xff, 0xd9]);

    final store = SourceMediaStore();

    expect(await store.isAvailable(image.path), isTrue);
    expect(await store.isAvailable('${directory.path}/missing.jpg'), isFalse);
    expect(
      await store.isAvailable('https://example.com/temporary.jpg'),
      isFalse,
    );
  });
}
