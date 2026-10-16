import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../../core/ids.dart';

/// Manual cover photos: one compressed photo per recipe; keep originals untouched.
class ManualRecipePhotoStore {
  ManualRecipePhotoStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directoryProvider;
  static const maxStoredBytes = 200 * 1024;
  static const maxEdge = 800;

  Future<Directory> _directory() async {
    final base = await _directoryProvider();
    final directory = Directory('${base.path}/manual_recipe_photos');
    await directory.create(recursive: true);
    return directory;
  }

  Future<String> save(Uint8List source) async {
    final bytes = await compute(compressManualRecipePhoto, source);
    final directory = await _directory();
    final file = File('${directory.path}/manual_${newId()}.jpg');
    try {
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
  }

  /// Only files created here may be removed, never gallery or other app images.
  Future<void> deleteOwned(String? path) async {
    if (path == null) return;
    final directory = await _directory();
    final file = File(path);
    if (file.parent.absolute.path != directory.absolute.path ||
        !RegExp(
          r'^manual_[a-fA-F0-9-]+\.jpg$',
        ).hasMatch(file.uri.pathSegments.last)) {
      return;
    }
    if (await file.exists()) {
      await file.delete();
    }
  }
}

Uint8List compressManualRecipePhoto(Uint8List source) {
  if (source.isEmpty || source.length > 20 * 1024 * 1024) {
    throw const FormatException('画像の容量が大きすぎます。別の画像を選んでください。');
  }
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(source);
  } catch (_) {
    throw const FormatException('この画像を読み込めません。別の画像を選んでください。');
  }
  if (decoded == null) {
    throw const FormatException('この画像を読み込めません。JPEGまたはPNGの画像を選んでください。');
  }
  final oriented = img.bakeOrientation(decoded);
  final longest = oriented.width > oriented.height
      ? oriented.width
      : oriented.height;
  var edge = longest > ManualRecipePhotoStore.maxEdge
      ? ManualRecipePhotoStore.maxEdge
      : longest;
  while (edge >= 1) {
    final resized = img.copyResize(
      oriented,
      width: oriented.width >= oriented.height ? edge : null,
      height: oriented.height > oriented.width ? edge : null,
      interpolation: img.Interpolation.average,
    );
    // Copy pixels into a new image so GPS/EXIF metadata is not retained.
    final clean = img.Image(
      width: resized.width,
      height: resized.height,
      numChannels: 3,
    );
    img.fill(clean, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(clean, resized);
    final bytes = Uint8List.fromList(img.encodeJpg(clean, quality: 72));
    if (bytes.length <= ManualRecipePhotoStore.maxStoredBytes) return bytes;
    if (edge == 1) break;
    edge = (edge * 0.8).floor().clamp(1, edge - 1).toInt();
  }
  throw const FormatException('画像を保存できませんでした。別の画像を選んでください。');
}
