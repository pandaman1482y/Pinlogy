import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image_lib;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// レシピの表示に必要な画像を、ユーザー専用の非公開Storageへ同期する。
///
/// クラウド上のJSONには端末固有のファイルパスを保存せず、
/// `recipe-media://...` 形式のオブジェクト参照だけを保存する。
class CloudRecipeMediaService {
  CloudRecipeMediaService(this._client);

  static const bucket = 'recipe-user-media';
  static const _scheme = 'recipe-media';
  static const _maxInputBytes = 2 * 1024 * 1024;
  static const _maxWidth = 800;
  static const _parallelMediaTasks = 4;
  static const _referenceCachePrefix = 'recipe_media_reference_v1_';
  static const _referenceIndexPrefix = 'recipe_media_reference_index_v1_';
  final SupabaseClient _client;

  Future<Map<String, dynamic>> prepareSnapshotForUpload(
    String ownerId,
    Map<String, dynamic> payload,
  ) async {
    final converted = await _convertForUpload(ownerId, payload);
    return Map<String, dynamic>.from(converted as Map);
  }

  Future<Map<String, dynamic>> materializeDownloadedSnapshot(
    String ownerId,
    Map<String, dynamic> payload,
  ) async {
    final converted = await _convertForDownload(ownerId, payload);
    final result = Map<String, dynamic>.from(converted as Map);
    await _pruneDownloadedMedia(ownerId, result);
    return result;
  }

  Future<dynamic> _convertForUpload(String ownerId, dynamic value) async {
    if (value is List) {
      return _mapLimited(value, (item) => _convertForUpload(ownerId, item));
    }
    if (value is! Map) return value;
    final output = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final raw = entry.value;
      if (_isImageKey(key) && raw is String) {
        output[key] = await _uploadLocalImage(ownerId, raw);
      } else {
        output[key] = await _convertForUpload(ownerId, raw);
      }
    }
    return output;
  }

  Future<dynamic> _convertForDownload(String ownerId, dynamic value) async {
    if (value is List) {
      return _mapLimited(value, (item) => _convertForDownload(ownerId, item));
    }
    if (value is! Map) return value;
    final output = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final raw = entry.value;
      if (_isImageKey(key) && raw is String) {
        output[key] = await _downloadCloudImage(ownerId, raw);
      } else {
        output[key] = await _convertForDownload(ownerId, raw);
      }
    }
    return output;
  }

  bool _isImageKey(String key) => key == 'coverImagePath' || key == 'imagePath';

  Future<List<dynamic>> _mapLimited(
    List<dynamic> values,
    Future<dynamic> Function(dynamic value) convert,
  ) async {
    final output = List<dynamic>.filled(values.length, null);
    var nextIndex = 0;
    Future<void> worker() async {
      while (nextIndex < values.length) {
        final index = nextIndex++;
        output[index] = await convert(values[index]);
      }
    }

    final workerCount = values.length < _parallelMediaTasks
        ? values.length
        : _parallelMediaTasks;
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return output;
  }

  Future<String> _uploadLocalImage(String ownerId, String raw) async {
    final value = raw.trim();
    if (value.isEmpty || value.startsWith('$_scheme://')) return value;
    final uri = Uri.tryParse(value);
    if (uri?.scheme == 'https' || value.startsWith('local://')) return value;
    try {
      final path = uri?.scheme == 'file' ? uri!.toFilePath() : value;
      final file = File(path);
      if (!await file.exists()) return value;
      final length = await file.length();
      if (length <= 0 || length > _maxInputBytes) return value;
      final modified = await file.lastModified();
      final referenceKey = _referenceCacheKey(
        ownerId,
        path,
        length,
        modified.millisecondsSinceEpoch,
      );
      final preferences = await SharedPreferences.getInstance();
      final cachedReference = preferences.getString(referenceKey);
      if (cachedReference?.startsWith('$_scheme://$ownerId/') == true) {
        return cachedReference!;
      }
      final source = await file.readAsBytes();
      final decoded = image_lib.decodeImage(source);
      if (decoded == null) return value;
      final resized = decoded.width > _maxWidth
          ? image_lib.copyResize(
              decoded,
              width: _maxWidth,
              interpolation: image_lib.Interpolation.average,
            )
          : decoded;
      final bytes = Uint8List.fromList(
        image_lib.encodeJpg(resized, quality: 72),
      );
      final digest = sha256.convert(bytes).toString();
      final objectPath = '$ownerId/${digest.substring(0, 2)}/$digest.jpg';
      await _client.storage
          .from(bucket)
          .uploadBinary(
            objectPath,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
              cacheControl: '31536000',
            ),
          );
      final reference = '$_scheme://$objectPath';
      await preferences.setString(referenceKey, reference);
      await _rememberReferenceKey(preferences, ownerId, referenceKey);
      return reference;
    } catch (_) {
      // 画像だけ同期できない場合も、レシピ本文の同期は継続する。
      return value;
    }
  }

  Future<String> _downloadCloudImage(String ownerId, String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri?.scheme != _scheme) return raw;
    final objectPath = '${uri!.host}${uri.path}';
    if (!objectPath.startsWith('$ownerId/')) return 'local://image-unavailable';
    try {
      final root = await getApplicationSupportDirectory();
      final filename = objectPath.split('/').last;
      final directory = Directory('${root.path}/recipe_cloud_media/$ownerId');
      await directory.create(recursive: true);
      final target = File('${directory.path}/$filename');
      if (await target.exists() && await target.length() > 0) {
        await _rememberDownloadedReference(ownerId, target, raw);
        return target.path;
      }
      final bytes = await _client.storage.from(bucket).download(objectPath);
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
      await _rememberDownloadedReference(ownerId, target, raw);
      return target.path;
    } catch (_) {
      // 次回同期時に再取得できるよう、クラウド参照を残す。
      return raw;
    }
  }

  String _referenceCacheKey(
    String ownerId,
    String path,
    int length,
    int modifiedMilliseconds,
  ) {
    final identity = sha256
        .convert('$ownerId\n$path\n$length\n$modifiedMilliseconds'.codeUnits)
        .toString();
    return '$_referenceCachePrefix$identity';
  }

  Future<void> _rememberDownloadedReference(
    String ownerId,
    File file,
    String reference,
  ) async {
    final length = await file.length();
    final modified = await file.lastModified();
    final preferences = await SharedPreferences.getInstance();
    final referenceKey = _referenceCacheKey(
      ownerId,
      file.path,
      length,
      modified.millisecondsSinceEpoch,
    );
    await preferences.setString(referenceKey, reference);
    await _rememberReferenceKey(preferences, ownerId, referenceKey);
  }

  Future<void> _rememberReferenceKey(
    SharedPreferences preferences,
    String ownerId,
    String key,
  ) async {
    final indexKey = '$_referenceIndexPrefix$ownerId';
    final values = preferences.getStringList(indexKey) ?? <String>[];
    if (values.contains(key)) return;
    await preferences.setStringList(indexKey, [...values, key]);
  }

  Future<void> _pruneDownloadedMedia(
    String ownerId,
    Map<String, dynamic> payload,
  ) async {
    try {
      final root = await getApplicationSupportDirectory();
      final directory = Directory('${root.path}/recipe_cloud_media/$ownerId');
      if (!await directory.exists()) return;
      final referenced = <String>{};
      void collect(dynamic value) {
        if (value is List) {
          for (final item in value) collect(item);
          return;
        }
        if (value is Map) {
          for (final entry in value.entries) {
            if (_isImageKey(entry.key.toString()) && entry.value is String) {
              referenced.add((entry.value as String).trim());
            } else {
              collect(entry.value);
            }
          }
        }
      }

      collect(payload);
      await for (final entity in directory.list()) {
        if (entity is File && !referenced.contains(entity.path)) {
          await entity.delete();
        }
      }
    } catch (_) {
      // キャッシュ整理失敗は表示・同期を止めない。
    }
  }

  static Future<void> clearLocalCache(String ownerId) async {
    try {
      final root = await getApplicationSupportDirectory();
      final directory = Directory('${root.path}/recipe_cloud_media/$ownerId');
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {
      // アカウント削除は画像キャッシュ削除失敗で止めない。
    }
    try {
      final preferences = await SharedPreferences.getInstance();
      final indexKey = '$_referenceIndexPrefix$ownerId';
      for (final key
          in preferences.getStringList(indexKey) ?? const <String>[]) {
        await preferences.remove(key);
      }
      await preferences.remove(indexKey);
    } catch (_) {
      // 参照キャッシュ削除失敗でもアカウント削除は継続する。
    }
  }
}
