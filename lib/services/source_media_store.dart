import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 共有元画像を一時URLやShare Extensionの作業領域から退避する。
class SourceMediaStore {
  static const maxImages = 5;
  static const maxImageBytes = 2 * 1024 * 1024;

  Future<List<String>> persist(
    String sourcePostId,
    Iterable<String> sources,
  ) async {
    final values = sources
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .take(maxImages)
        .toList(growable: false);
    if (values.isEmpty) return const [];
    try {
      final root = await getApplicationSupportDirectory();
      final safeId = sourcePostId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final directory = Directory('${root.path}/source_media/$safeId');
      await directory.create(recursive: true);
      final saved = <String>[];
      for (var index = 0; index < values.length; index++) {
        final value = values[index];
        final existing = File(value);
        if (await existing.exists() &&
            _isInside(existing.path, directory.path)) {
          saved.add(existing.path);
          continue;
        }
        final loaded = await _load(value);
        if (loaded == null) continue;
        final target = File(
          '${directory.path}/image_$index.${loaded.extension}',
        );
        final temporary = File('${target.path}.tmp');
        await temporary.writeAsBytes(loaded.bytes, flush: true);
        if (await target.exists()) await target.delete();
        await temporary.rename(target.path);
        saved.add(target.path);
      }
      return saved;
    } catch (_) {
      // 保存領域を利用できないテスト環境では元の値を維持する。
      return values;
    }
  }

  Future<_LoadedImage?> _load(String source) async {
    final data = RegExp(
      r'^data:image/(jpeg|png|webp);base64,(.+)$',
    ).firstMatch(source);
    if (data != null) {
      final bytes = base64Decode(data.group(2)!);
      if (!_validSize(bytes.length)) return null;
      return _LoadedImage(
        bytes,
        data.group(1) == 'jpeg' ? 'jpg' : data.group(1)!,
      );
    }

    final uri = Uri.tryParse(source);
    if (uri?.scheme == 'https') {
      final response = await http
          .get(uri!)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 ||
          !_validSize(response.bodyBytes.length)) {
        return null;
      }
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      final extension = contentType.contains('png')
          ? 'png'
          : contentType.contains('webp')
          ? 'webp'
          : contentType.contains('jpeg') || contentType.contains('jpg')
          ? 'jpg'
          : null;
      return extension == null
          ? null
          : _LoadedImage(response.bodyBytes, extension);
    }

    final file = File(uri?.scheme == 'file' ? uri!.toFilePath() : source);
    if (!await file.exists()) return null;
    final length = await file.length();
    if (!_validSize(length)) return null;
    final extension = _extensionFor(file.path);
    return extension == null
        ? null
        : _LoadedImage(await file.readAsBytes(), extension);
  }

  bool _validSize(int length) => length > 0 && length <= maxImageBytes;

  static bool _isInside(String file, String directory) => File(
    file,
  ).absolute.path.startsWith('${Directory(directory).absolute.path}/');

  static String? _extensionFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'jpg';
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    return null;
  }
}

class _LoadedImage {
  const _LoadedImage(this.bytes, this.extension);
  final List<int> bytes;
  final String extension;
}
