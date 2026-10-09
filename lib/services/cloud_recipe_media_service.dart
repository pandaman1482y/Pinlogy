import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image_lib;
import 'package:path_provider/path_provider.dart';
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
    return Map<String, dynamic>.from(converted as Map);
  }

  Future<dynamic> _convertForUpload(String ownerId, dynamic value) async {
    if (value is List) {
      final output = <dynamic>[];
      for (final item in value) {
        output.add(await _convertForUpload(ownerId, item));
      }
      return output;
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
      final output = <dynamic>[];
      for (final item in value) {
        output.add(await _convertForDownload(ownerId, item));
      }
      return output;
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
      return '$_scheme://$objectPath';
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
        return target.path;
      }
      final bytes = await _client.storage.from(bucket).download(objectPath);
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
      return target.path;
    } catch (_) {
      // 次回同期時に再取得できるよう、クラウド参照を残す。
      return raw;
    }
  }
}
