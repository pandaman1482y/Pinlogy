import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 共有元画像を一時URLやShare Extensionの作業領域から退避する。
class SourceMediaStore {
  static const maxImages = 5;
  static const maxImageBytes = 2 * 1024 * 1024;
  static const maxTotalBytes = 8 * 1024 * 1024;

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
      var savedBytes = 0;
      for (var index = 0; index < values.length; index++) {
        final value = values[index];
        final existing = File(value);
        if (await existing.exists() &&
            _isInside(existing.path, directory.path)) {
          final length = await existing.length();
          if (!_validSize(length) || savedBytes + length > maxTotalBytes) break;
          saved.add(existing.path);
          savedBytes += length;
          continue;
        }
        final loaded = await _load(value);
        if (loaded == null) continue;
        if (savedBytes + loaded.bytes.length > maxTotalBytes) break;
        final target = File(
          '${directory.path}/image_$index.${loaded.extension}',
        );
        final temporary = File('${target.path}.tmp');
        await temporary.writeAsBytes(loaded.bytes, flush: true);
        if (await target.exists()) await target.delete();
        await temporary.rename(target.path);
        saved.add(target.path);
        savedBytes += loaded.bytes.length;
      }
      return saved;
    } catch (_) {
      // 保存領域を利用できないテスト環境では元の値を維持する。
      return values;
    }
  }

  Future<bool> isAvailable(String? rawPath) async {
    final value = rawPath?.trim();
    if (value == null || value.isEmpty) return false;
    final uri = Uri.tryParse(value);
    if (uri?.scheme == 'https') return false;
    if (value.startsWith('local://')) return false;
    try {
      final path = uri?.scheme == 'file' ? uri!.toFilePath() : value;
      final file = File(path);
      return await file.exists() && await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteForPost(
    String sourcePostId, {
    Set<String> protectedPaths = const {},
  }) async {
    try {
      final root = await getApplicationSupportDirectory();
      final safeId = sourcePostId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final mediaDirectory = Directory('${root.path}/source_media/$safeId');
      if (await mediaDirectory.exists()) {
        await for (final entity in mediaDirectory.list()) {
          if (entity is File && !protectedPaths.contains(entity.path)) {
            await entity.delete();
          }
        }
        if (await mediaDirectory.list().isEmpty) await mediaDirectory.delete();
      }
      final previewDirectory = Directory('${root.path}/source_previews');
      if (await previewDirectory.exists()) {
        await for (final entity in previewDirectory.list()) {
          if (entity is! File) continue;
          final name = entity.uri.pathSegments.last;
          if (name.startsWith('${safeId}_') &&
              !protectedPaths.contains(entity.path)) {
            await entity.delete();
          }
        }
      }
    } catch (_) {
      // 投稿データの削除は、補助画像の掃除失敗で止めない。
    }
  }

  Future<_LoadedImage?> _load(String source) async {
    final data = RegExp(
      r'^data:image/(jpeg|png|webp);base64,(.+)$',
    ).firstMatch(source);
    if (data != null) {
      final bytes = base64Decode(data.group(2)!);
      if (!_validSize(bytes.length)) return null;
      final extension = data.group(1) == 'jpeg' ? 'jpg' : data.group(1)!;
      if (!_matchesImageSignature(bytes, extension)) return null;
      return _LoadedImage(
        bytes,
        extension,
      );
    }

    final uri = Uri.tryParse(source);
    if (uri?.scheme == 'https' && _isAllowedRemoteHost(uri!.host)) {
      final response = await _getAllowedRemote(uri);
      if (response == null) return null;
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
      return extension == null ||
              !_matchesImageSignature(response.bodyBytes, extension)
          ? null
          : _LoadedImage(response.bodyBytes, extension);
    }

    final file = File(uri?.scheme == 'file' ? uri!.toFilePath() : source);
    if (!await file.exists()) return null;
    final length = await file.length();
    if (!_validSize(length)) return null;
    final extension = _extensionFor(file.path);
    if (extension == null) return null;
    final bytes = await file.readAsBytes();
    return _matchesImageSignature(bytes, extension)
        ? _LoadedImage(bytes, extension)
        : null;
  }

  bool _validSize(int length) => length > 0 && length <= maxImageBytes;

  Future<http.Response?> _getAllowedRemote(Uri initialUri) async {
    var current = initialUri;
    for (var redirect = 0; redirect <= 3; redirect++) {
      if (current.scheme != 'https' || !_isAllowedRemoteHost(current.host)) {
        return null;
      }
      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers['Accept'] = 'image/jpeg,image/png,image/webp';
      final streamed = await request.send().timeout(
        const Duration(seconds: 10),
      );
      if (streamed.isRedirect) {
        final location = streamed.headers['location'];
        if (location == null || redirect == 3) return null;
        current = current.resolve(location);
        continue;
      }
      final declaredLength = streamed.contentLength;
      if (declaredLength != null && declaredLength > maxImageBytes) return null;
      final bytes = await streamed.stream
          .expand((chunk) => chunk)
          .take(maxImageBytes + 1)
          .toList()
          .timeout(const Duration(seconds: 10));
      if (bytes.length > maxImageBytes) return null;
      return http.Response.bytes(
        bytes,
        streamed.statusCode,
        headers: streamed.headers,
        request: request,
      );
    }
    return null;
  }

  static bool _matchesImageSignature(List<int> bytes, String extension) {
    if (extension == 'jpg') {
      return bytes.length >= 3 &&
          bytes[0] == 0xff &&
          bytes[1] == 0xd8 &&
          bytes[2] == 0xff;
    }
    if (extension == 'png') {
      return bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4e &&
          bytes[3] == 0x47;
    }
    if (extension == 'webp') {
      return bytes.length >= 12 &&
          String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
    }
    return false;
  }

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

  static bool _isAllowedRemoteHost(String rawHost) {
    final host = rawHost.toLowerCase();
    return const [
      'tiktokcdn.com',
      'tiktokcdn-us.com',
      'muscdn.com',
      'byteimg.com',
      'cdninstagram.com',
      'fbcdn.net',
      'ytimg.com',
    ].any((domain) => host == domain || host.endsWith('.$domain'));
  }
}

class _LoadedImage {
  const _LoadedImage(this.bytes, this.extension);
  final List<int> bytes;
  final String extension;
}
