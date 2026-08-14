import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'ai_analysis_consent.dart';
import 'location_services.dart';

/// 明示同意時だけEdge Functionで解析し、未同意・障害時は端末解析へ戻す。
class AiPostAnalysisService implements PostAnalysisService {
  AiPostAnalysisService({required this.fallback, http.Client? client})
    : _client = client ?? http.Client();

  final PostAnalysisService fallback;
  final http.Client _client;
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _key = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _cachePrefix = 'ai_analysis_cache_v1_';
  static const _cacheIndexKey = 'ai_analysis_cache_index_v1';
  static const _deviceIdKey = 'ai_quota_device_id_v1';

  static bool get backendConfigured =>
      _url.startsWith('https://') && _key.isNotEmpty;

  @override
  Future<PostAnalysisResponse> analyze(PostAnalysisRequest request) async {
    final local = await fallback.analyze(request);
    if (!await AiAnalysisConsent().hasConsented() || !backendConfigured) {
      return local;
    }
    final cacheKey = _cacheKey(request, local.evidenceText);
    final cached = await _readCache(cacheKey);
    final needsTikTokPhotoPreview =
        request.url?.contains('/photo/') ?? false;
    if (cached != null && !needsTikTokPhotoPreview) {
      return PostAnalysisResponse(
        sourcePostId: cached.sourcePostId,
        candidates: cached.candidates,
        rawSummary: cached.rawSummary,
        evidenceText: cached.evidenceText,
        analysisSource: 'ai_cache',
      );
    }
    try {
      final uri = Uri.parse(
        '${_url.replaceAll(RegExp(r'/$'), '')}/functions/v1/analyze-post',
      );
      final imageDataUrls = await _readImages(request.imageUrls);
      final deviceId = await _deviceId();
      final response = await _client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $_key',
              'apikey': _key,
              'Content-Type': 'application/json',
              'X-Pinlogy-Device': deviceId,
            },
            body: jsonEncode({
              ...request.toJson(),
              'local_candidates': local.candidates
                  .map((e) => e.toJson())
                  .toList(),
              'local_summary': local.rawSummary,
              'ocr_text': local.evidenceText,
              'image_data_urls': imageDataUrls,
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode == 401 || response.statusCode == 403) {
        return _asFallback(local, analysisSource: 'auth_fallback');
      }
      if (response.statusCode == 404) {
        return _asFallback(local, analysisSource: 'function_missing_fallback');
      }
      if (response.statusCode == 429) {
        return _asFallback(local, analysisSource: 'quota_fallback');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _asFallback(local, analysisSource: 'server_fallback');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return _asFallback(local, analysisSource: 'invalid_response_fallback');
      }
      final previewImagePath = await _savePreviewImage(
        request.sourcePostId,
        decoded,
      );
      final result = PostAnalysisResponse.fromJson({
        ...decoded,
        'preview_image_path': previewImagePath,
      });
      if (result.candidates.isEmpty && local.candidates.isNotEmpty) {
        return _asFallback(local, analysisSource: 'ai_no_match');
      }
      await _writeCache(cacheKey, result);
      return result;
    } on TimeoutException {
      return _asFallback(local, analysisSource: 'timeout_fallback');
    } on SocketException {
      return _asFallback(local, analysisSource: 'network_fallback');
    } catch (_) {
      return _asFallback(local, analysisSource: 'invalid_response_fallback');
    }
  }

  Future<String?> _savePreviewImage(
    String sourcePostId,
    Map<String, dynamic> response,
  ) async {
    try {
      final media = response['shared_media'];
      if (media is! Map) return null;
      final dataUrl = media['thumbnail_data_url']?.toString();
      if (dataUrl == null) return null;
      final match = RegExp(
        r'^data:image/(jpeg|png|webp);base64,(.+)$',
      ).firstMatch(dataUrl);
      if (match == null) return null;
      final bytes = base64Decode(match.group(2)!);
      if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) return null;
      final directory = Directory(
        '${(await getApplicationSupportDirectory()).path}/source_previews',
      );
      await directory.create(recursive: true);
      final extension = match.group(1) == 'jpeg' ? 'jpg' : match.group(1)!;
      final safeId = sourcePostId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final file = File('${directory.path}/$safeId.$extension');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<String> _deviceId() async {
    final preferences = await SharedPreferences.getInstance();
    final current = preferences.getString(_deviceIdKey);
    if (current != null && current.isNotEmpty) return current;
    const uuid = Uuid();
    final created = uuid.v4();
    await preferences.setString(_deviceIdKey, created);
    return created;
  }

  PostAnalysisResponse _asFallback(
    PostAnalysisResponse local, {
    String analysisSource = 'local_fallback',
  }) {
    return PostAnalysisResponse(
      sourcePostId: local.sourcePostId,
      candidates: local.candidates,
      rawSummary: local.rawSummary,
      evidenceText: local.evidenceText,
      analysisSource: analysisSource,
    );
  }

  String _cacheKey(PostAnalysisRequest request, String? evidenceText) {
    final input = [
      request.url ?? '',
      request.text ?? '',
      evidenceText ?? '',
      ...request.imageUrls,
    ].join('\u001f').trim().toLowerCase();
    // Stable FNV-1a hash avoids adding a cryptography dependency for a local cache key.
    var hash = 0xcbf29ce484222325;
    for (final unit in utf8.encode(input)) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16);
  }

  Future<PostAnalysisResponse?> _readCache(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('$_cachePrefix$key');
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      final storedAt = DateTime.parse(value['stored_at'] as String);
      if (DateTime.now().difference(storedAt).inDays >= 30) {
        await preferences.remove('$_cachePrefix$key');
        return null;
      }
      return PostAnalysisResponse.fromJson(
        Map<String, dynamic>.from(value['result'] as Map),
      );
    } catch (_) {
      await preferences.remove('$_cachePrefix$key');
      return null;
    }
  }

  Future<void> _writeCache(String key, PostAnalysisResponse result) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_cachePrefix$key',
      jsonEncode({
        'stored_at': DateTime.now().toUtc().toIso8601String(),
        'result': {
          'source_post_id': result.sourcePostId,
          'candidates': result.candidates.map((item) => item.toJson()).toList(),
          'raw_summary': result.rawSummary,
          'evidence_text': result.evidenceText,
          'analysis_source': result.analysisSource,
        },
      }),
    );
    final index = preferences.getStringList(_cacheIndexKey) ?? <String>[];
    index.remove(key);
    index.insert(0, key);
    for (final expired in index.skip(30)) {
      await preferences.remove('$_cachePrefix$expired');
    }
    await preferences.setStringList(_cacheIndexKey, index.take(30).toList());
  }

  Future<List<String>> _readImages(List<String> paths) async {
    final encoded = <String>[];
    for (final rawPath in paths.take(5)) {
      try {
        final remote = Uri.tryParse(rawPath);
        if (remote?.scheme == 'https' && _isAllowedPreviewHost(remote!.host)) {
          final response = await _client
              .get(remote, headers: const {'Accept': 'image/*'})
              .timeout(const Duration(seconds: 8));
          final contentType = response.headers['content-type'] ?? '';
          final bytes = response.bodyBytes;
          if (response.statusCode == 200 &&
              _isAllowedPreviewHost(response.request?.url.host ?? '') &&
              contentType.startsWith('image/') &&
              bytes.isNotEmpty &&
              bytes.length <= 2 * 1024 * 1024) {
            final mime = contentType.split(';').first.toLowerCase();
            if (mime == 'image/jpeg' ||
                mime == 'image/png' ||
                mime == 'image/webp') {
              encoded.add('data:$mime;base64,${base64Encode(bytes)}');
            }
          }
          continue;
        }
        final path = rawPath.startsWith('file://')
            ? Uri.parse(rawPath).toFilePath()
            : rawPath;
        if (path.startsWith('local://')) continue;
        final file = File(path);
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        // 通信量とEdge Functionのメモリを守る。
        if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) continue;
        final lower = path.toLowerCase();
        final mime = lower.endsWith('.png')
            ? 'image/png'
            : lower.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
        encoded.add('data:$mime;base64,${base64Encode(bytes)}');
      } catch (_) {
        // 読めない画像があっても投稿文・端末OCRで解析を続ける。
      }
    }
    return encoded;
  }

  bool _isAllowedPreviewHost(String rawHost) {
    final host = rawHost.toLowerCase();
    return const [
      'tiktokcdn.com',
      'tiktokcdn-us.com',
      'muscdn.com',
      'ytimg.com',
    ].any((domain) => host == domain || host.endsWith('.$domain'));
  }
}
