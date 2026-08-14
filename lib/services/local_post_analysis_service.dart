import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'location_services.dart';

/// 投稿文と端末内OCRから住所を優先して候補を作る実解析。
/// 画像・認識文字は端末外へ送信しない。
class LocalPostAnalysisService implements PostAnalysisService {
  @override
  Future<PostAnalysisResponse> analyze(PostAnalysisRequest request) async {
    final parts = <_TextPart>[];
    if (request.text?.trim().isNotEmpty == true) {
      parts.add(_TextPart(request.text!.trim(), '投稿文'));
    }
    for (var i = 0; i < request.imageUrls.length; i++) {
      final text = await _readImage(request.imageUrls[i]);
      if (text.trim().isNotEmpty) parts.add(_TextPart(text, '画像${i + 1}枚目'));
    }

    final drafts = parts.expand(_extract);
    final shortReason = _summarize(parts);
    final hours = _extractOpeningHours(parts);
    final unique = <String, _CandidateDraft>{};
    for (final draft in drafts) {
      final key = _normalize(draft.address ?? draft.name);
      if (key.isNotEmpty) unique.putIfAbsent(key, () => draft);
    }
    final candidates = unique.values
        .take(10)
        .map(
          (draft) => ExtractionCandidate(
            name: draft.name,
            address: draft.address,
            category: _categoryFor(
              '${draft.name} ${parts.map((p) => p.text).join(' ')}',
            ),
            genres: _genresFor(
              '${draft.name} ${parts.map((p) => p.text).join(' ')}',
            ),
            postAddress: draft.address,
            reason: shortReason,
            evidenceSummary: draft.address == null
                ? '店名候補の取得元：${draft.source}。住所は手動確認してください'
                : '住所の取得元：${draft.source} / 店名候補も同じ投稿から抽出',
            evidenceImageIndex: _imageIndexForSource(draft.source),
            confidencePercent: draft.address == null ? 50 : 78,
            match: PlaceMatchConfidence.needsReview,
            openingTimeMinutes: hours?.$1,
            closingTimeMinutes: hours?.$2,
            closedWeekdays: _extractClosedWeekdays(parts),
          ),
        )
        .toList();

    if (candidates.isEmpty) {
      final fallback = _fallbackName(parts);
      if (fallback != null) {
        candidates.add(
          ExtractionCandidate(
            name: fallback,
            category: _categoryFor(
              '$fallback ${parts.map((p) => p.text).join(' ')}',
            ),
            genres: _genresFor(
              '$fallback ${parts.map((p) => p.text).join(' ')}',
            ),
            reason: shortReason,
            evidenceSummary: '住所を特定できなかったため確認が必要です',
            confidencePercent: 40,
            match: PlaceMatchConfidence.needsReview,
            openingTimeMinutes: hours?.$1,
            closingTimeMinutes: hours?.$2,
            closedWeekdays: _extractClosedWeekdays(parts),
          ),
        );
      }
    }
    return PostAnalysisResponse(
      sourcePostId: request.sourcePostId,
      rawSummary: parts.any((p) => p.source.startsWith('画像'))
          ? '投稿文と画像を端末内で解析しました'
          : '投稿文を端末内で解析しました',
      candidates: candidates,
      evidenceText: parts.map((part) => part.text).join('\n\n'),
    );
  }

  String? _categoryFor(String text) {
    if (_genresFor(text).isNotEmpty) return '飲食店';
    if (RegExp(r'ホテル|旅館|宿泊|民宿').hasMatch(text)) return '宿泊';
    if (RegExp(r'神社|寺|公園|美術館|博物館|展望|水族館|動物園|観光').hasMatch(text)) {
      return '観光・レジャー';
    }
    if (RegExp(r'ショップ|雑貨|百貨店|ショッピング|市場').hasMatch(text)) return '買い物';
    return null;
  }

  int? _imageIndexForSource(String source) {
    final match = RegExp(r'^画像(\d+)枚目$').firstMatch(source);
    final oneBased = int.tryParse(match?.group(1) ?? '');
    return oneBased == null ? null : oneBased - 1;
  }

  List<String> _genresFor(String text) {
    const genres = <String, List<String>>{
      'カフェ': ['カフェ', '喫茶', 'コーヒー', '珈琲'],
      'スイーツ': ['スイーツ', 'ケーキ', 'パフェ', 'クレープ', '和菓子'],
      'ラーメン': ['ラーメン', '中華そば', 'つけ麺'],
      '寿司': ['寿司', '鮨', 'すし'],
      '焼肉': ['焼肉', 'ホルモン'],
      '居酒屋': ['居酒屋', '酒場'],
      '和食': ['和食', '懐石', '割烹', '定食', 'うどん', 'そば'],
      '洋食': ['洋食', 'オムライス', 'ハンバーグ'],
      'イタリアン': ['イタリアン', 'パスタ', 'ピザ'],
      '中華': ['中華', '餃子', '麻婆'],
      'カレー': ['カレー'],
      'パン': ['パン', 'ベーカリー'],
    };
    return genres.entries
        .where((entry) => entry.value.any(text.contains))
        .map((entry) => entry.key)
        .take(3)
        .toList();
  }

  Future<String> _readImage(String rawPath) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return '';
    }
    String? temporaryPath;
    var path = rawPath.startsWith('file://')
        ? Uri.parse(rawPath).toFilePath()
        : rawPath;
    final remote = Uri.tryParse(rawPath);
    if (remote?.scheme == 'https' && _isAllowedPreviewHost(remote!.host)) {
      try {
        final response = await http
            .get(remote, headers: const {'Accept': 'image/*'})
            .timeout(const Duration(seconds: 8));
        final contentType = response.headers['content-type'] ?? '';
        if (response.statusCode != 200 ||
            !_isAllowedPreviewHost(response.request?.url.host ?? '') ||
            !contentType.startsWith('image/') ||
            response.bodyBytes.isEmpty ||
            response.bodyBytes.length > 2 * 1024 * 1024) {
          return '';
        }
        final file = File(
          '${Directory.systemTemp.path}/pinlogy_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
        );
        await file.writeAsBytes(response.bodyBytes, flush: true);
        path = file.path;
        temporaryPath = file.path;
      } catch (_) {
        return '';
      }
    }
    if (path.startsWith('local://') || !await File(path).exists()) return '';
    final recognizer = TextRecognizer(script: TextRecognitionScript.japanese);
    try {
      return (await recognizer.processImage(InputImage.fromFilePath(path)))
          .text;
    } catch (_) {
      return '';
    } finally {
      await recognizer.close();
      if (temporaryPath != null) {
        try {
          await File(temporaryPath).delete();
        } catch (_) {}
      }
    }
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

  List<_CandidateDraft> _extract(_TextPart part) {
    final lines = part.text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final result = <_CandidateDraft>[];
    for (var i = 0; i < lines.length; i++) {
      final address = _addressFrom(lines[i]);
      if (address == null) continue;
      result.add(
        _CandidateDraft(
          name: _nearbyName(lines, i, address) ?? '名称を確認してください',
          address: address,
          source: part.source,
        ),
      );
    }
    return result;
  }

  String? _addressFrom(String line) {
    final cleaned = line
        .replaceFirst(RegExp(r'^(住所|所在地|場所|アクセス)\s*[:：]?\s*'), '')
        .replaceFirst(RegExp(r'^〒\s*\d{3}[-ー]?\d{4}\s*'), '')
        .trim();
    final hasPrefecture = RegExp(
      r'(北海道|東京都|京都府|大阪府|青森県|岩手県|宮城県|秋田県|山形県|福島県|茨城県|栃木県|群馬県|埼玉県|千葉県|神奈川県|新潟県|富山県|石川県|福井県|山梨県|長野県|岐阜県|静岡県|愛知県|三重県|滋賀県|兵庫県|奈良県|和歌山県|鳥取県|島根県|岡山県|広島県|山口県|徳島県|香川県|愛媛県|高知県|福岡県|佐賀県|長崎県|熊本県|大分県|宮崎県|鹿児島県|沖縄県)',
    ).hasMatch(cleaned);
    final specific = RegExp(r'(市|区|町|村).*(丁目|番地|番|号|\d)').hasMatch(cleaned);
    if (!hasPrefecture || !specific || cleaned.length > 100) return null;
    return cleaned.replaceAll(RegExp(r'\s*[|｜].*$'), '').trim();
  }

  String? _nearbyName(List<String> lines, int addressIndex, String address) {
    final sameLine = lines[addressIndex].replaceAll(address, '').trim();
    if (_isName(sameLine)) return sameLine;
    for (final index in [
      addressIndex - 1,
      addressIndex + 1,
      addressIndex - 2,
    ]) {
      if (index >= 0 && index < lines.length && _isName(lines[index])) {
        return lines[index];
      }
    }
    return null;
  }

  bool _isName(String value) {
    if (value.isEmpty || value.length > 60) return false;
    if (value.startsWith('http') ||
        value.startsWith('#') ||
        value.startsWith('@')) {
      return false;
    }
    if (RegExp(r'^(共有された|TikTok|Instagram|おすすめ|PR|広告)').hasMatch(value)) {
      return false;
    }
    if (_addressFrom(value) != null) return false;
    return RegExp(r'[ぁ-んァ-ヶ一-龠A-Za-z]').hasMatch(value);
  }

  String? _fallbackName(List<_TextPart> parts) {
    for (final part in parts) {
      for (final line in part.text.split(RegExp(r'[\r\n]+'))) {
        final value = line.trim();
        if (_isName(value)) return value;
      }
    }
    return null;
  }

  String _summarize(List<_TextPart> parts) {
    final candidates = parts
        .expand((part) => part.text.split(RegExp(r'[\r\n。！？!?]+')))
        .map(
          (value) => value
              .replaceAll(RegExp(r'https?://\S+|#[^\s#]+|@[^\s@]+'), '')
              .trim(),
        )
        .where((value) => value.length >= 4 && _addressFrom(value) == null)
        .where((value) => !RegExp(r'^(住所|所在地|アクセス|営業時間)').hasMatch(value));
    final value = candidates.isEmpty ? '共有された投稿で気になった場所' : candidates.first;
    return value.length <= 42 ? value : '${value.substring(0, 41)}…';
  }

  (int, int)? _extractOpeningHours(List<_TextPart> parts) {
    final text = parts.map((part) => part.text).join('\n');
    final match = RegExp(
      r'(?:営業時間[^0-9]*)?(\d{1,2})[:：](\d{2})\s*[〜~～\-ー]\s*(\d{1,2})[:：](\d{2})',
    ).firstMatch(text);
    if (match == null) return null;
    final open = int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
    final close = int.parse(match.group(3)!) * 60 + int.parse(match.group(4)!);
    if (open > 1439 || close > 1439) return null;
    return (open, close);
  }

  List<int> _extractClosedWeekdays(List<_TextPart> parts) {
    final text = parts.map((part) => part.text).join(' ');
    final match = RegExp(r'(?:定休日|休業日)\s*[:：]?\s*([月火水木金土日](?:曜(?:日)?)?)')
        .firstMatch(text);
    if (match == null) return const [];
    const names = '月火水木金土日';
    final weekday = names.indexOf(match.group(1)![0]);
    return weekday < 0 ? const [] : [weekday + 1];
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s　\-ー,，.。]'), '');
}

class _TextPart {
  const _TextPart(this.text, this.source);
  final String text;
  final String source;
}

class _CandidateDraft {
  const _CandidateDraft({
    required this.name,
    required this.source,
    this.address,
  });
  final String name;
  final String source;
  final String? address;
}
