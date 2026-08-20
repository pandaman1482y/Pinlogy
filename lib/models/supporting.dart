import '../core/ids.dart';
import 'enums.dart';

class Tag {
  Tag({String? id, required this.name}) : id = id ?? newId();

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Tag.fromJson(Map<String, dynamic> json) =>
      Tag(id: json['id'] as String, name: json['name'] as String);
}

class PlaceTag {
  PlaceTag({String? id, required this.placeId, required this.tagId})
    : id = id ?? newId();

  final String id;
  final String placeId;
  final String tagId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'placeId': placeId,
    'tagId': tagId,
  };

  factory PlaceTag.fromJson(Map<String, dynamic> json) => PlaceTag(
    id: json['id'] as String,
    placeId: json['placeId'] as String,
    tagId: json['tagId'] as String,
  );
}

class MapMember {
  MapMember({
    String? id,
    required this.mapId,
    required this.userId,
    this.role = 'owner',
    DateTime? joinedAt,
  }) : id = id ?? newId(),
       joinedAt = joinedAt ?? DateTime.now();

  final String id;
  final String mapId;
  final String userId;
  final String role;
  final DateTime joinedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'mapId': mapId,
    'userId': userId,
    'role': role,
    'joinedAt': joinedAt.toIso8601String(),
  };

  factory MapMember.fromJson(Map<String, dynamic> json) => MapMember(
    id: json['id'] as String,
    mapId: json['mapId'] as String,
    userId: json['userId'] as String,
    role: (json['role'] as String?) ?? 'owner',
    joinedAt: DateTime.parse(json['joinedAt'] as String),
  );
}

/// 投稿解析から得た場所候補（UI選択用）。
class ExtractionCandidate {
  ExtractionCandidate({
    String? id,
    required this.name,
    this.address,
    this.reason,
    this.category,
    this.genres = const [],
    this.evidenceSummary,
    this.evidenceImageIndex,
    this.confidencePercent,
    this.match = PlaceMatchConfidence.high,
    this.hasAddressMismatch = false,
    this.postAddress,
    this.searchCandidateName,
    this.searchCandidateAddress,
    this.latitude,
    this.longitude,
    this.mapPinX,
    this.mapPinY,
    this.openingTimeMinutes,
    this.closingTimeMinutes,
    this.closedWeekdays = const [],
  }) : id = id ?? newId();

  final String id;
  final String name;
  final String? address;
  final String? reason;
  final String? category;
  final List<String> genres;
  final String? evidenceSummary;
  final int? evidenceImageIndex;
  final int? confidencePercent;
  final PlaceMatchConfidence match;
  final bool hasAddressMismatch;
  final String? postAddress;
  final String? searchCandidateName;
  final String? searchCandidateAddress;
  final double? latitude;
  final double? longitude;
  final double? mapPinX;
  final double? mapPinY;
  final int? openingTimeMinutes;
  final int? closingTimeMinutes;
  final List<int> closedWeekdays;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'reason': reason,
    'category': category,
    'genres': genres,
    'evidenceSummary': evidenceSummary,
    'evidenceImageIndex': evidenceImageIndex,
    'confidencePercent': confidencePercent,
    'match': match.name,
    'hasAddressMismatch': hasAddressMismatch,
    'postAddress': postAddress,
    'searchCandidateName': searchCandidateName,
    'searchCandidateAddress': searchCandidateAddress,
    'latitude': latitude,
    'longitude': longitude,
    'mapPinX': mapPinX,
    'mapPinY': mapPinY,
    'openingTimeMinutes': openingTimeMinutes,
    'closingTimeMinutes': closingTimeMinutes,
    'closedWeekdays': closedWeekdays,
  };

  factory ExtractionCandidate.fromJson(Map<String, dynamic> json) =>
      ExtractionCandidate(
        id: json['id'] as String?,
        name: json['name'] as String,
        address: json['address'] as String?,
        reason: json['reason'] as String?,
        category: json['category'] as String?,
        genres: ((json['genres'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
        evidenceSummary: json['evidenceSummary'] as String?,
        evidenceImageIndex: (json['evidenceImageIndex'] as num?)?.toInt(),
        confidencePercent: json['confidencePercent'] as int?,
        match: PlaceMatchConfidence.fromName(json['match'] as String?),
        hasAddressMismatch: (json['hasAddressMismatch'] as bool?) ?? false,
        postAddress: json['postAddress'] as String?,
        searchCandidateName: json['searchCandidateName'] as String?,
        searchCandidateAddress: json['searchCandidateAddress'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        mapPinX: (json['mapPinX'] as num?)?.toDouble(),
        mapPinY: (json['mapPinY'] as num?)?.toDouble(),
        openingTimeMinutes: json['openingTimeMinutes'] as int?,
        closingTimeMinutes: json['closingTimeMinutes'] as int?,
        closedWeekdays: ((json['closedWeekdays'] as List?) ?? const [])
            .whereType<num>()
            .map((value) => value.toInt())
            .toList(),
      );
}

/// AI解析APIのリクエスト／レスポンス型（バックエンド接続用）。
class PostAnalysisRequest {
  const PostAnalysisRequest({
    required this.sourcePostId,
    this.url,
    this.text,
    this.imageUrls = const [],
    this.imageIndexes = const [],
    this.selectedImagesOnly = false,
    this.locale = 'ja-JP',
  });

  final String sourcePostId;
  final String? url;
  final String? text;
  final List<String> imageUrls;
  final List<int> imageIndexes;
  final bool selectedImagesOnly;
  final String locale;

  Map<String, dynamic> toJson() => {
    'source_post_id': sourcePostId,
    'url': url,
    'text': text,
    'image_urls': imageUrls,
    'image_indexes': imageIndexes,
    'selected_images_only': selectedImagesOnly,
    'locale': locale,
  };
}

class PostAnalysisResponse {
  const PostAnalysisResponse({
    required this.sourcePostId,
    required this.candidates,
    this.rawSummary,
    this.evidenceText,
    this.analysisSource = 'local',
    this.previewImagePath,
    this.previewImagePaths = const [],
  });

  final String sourcePostId;
  final List<ExtractionCandidate> candidates;
  final String? rawSummary;

  /// 端末OCRと投稿文を結合したAI解析用テキスト。端末内解析では保存しない。
  final String? evidenceText;
  final String analysisSource;
  final String? previewImagePath;
  final List<String> previewImagePaths;

  factory PostAnalysisResponse.fromJson(Map<String, dynamic> json) {
    final list = (json['candidates'] as List? ?? const [])
        .map((e) => ExtractionCandidate.fromJson(e as Map<String, dynamic>))
        .toList();
    return PostAnalysisResponse(
      sourcePostId: json['source_post_id'] as String,
      candidates: list,
      rawSummary: json['raw_summary'] as String?,
      evidenceText: json['evidence_text'] as String?,
      analysisSource: json['analysis_source'] as String? ?? 'ai',
      previewImagePath: json['preview_image_path'] as String?,
      previewImagePaths: ((json['preview_image_paths'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
    );
  }
}
