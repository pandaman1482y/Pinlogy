import '../models/models.dart';

/// ジオコーディング（バックエンド経由想定）。キーはアプリに埋め込まない。
abstract class GeocodingService {
  Future<GeoResult?> geocodeAddress(String address);
  Future<GeoResult?> reverseGeocode(double latitude, double longitude);
}

class GeoResult {
  const GeoResult({
    required this.latitude,
    required this.longitude,
    this.formattedAddress,
  });

  final double latitude;
  final double longitude;
  final String? formattedAddress;
}

class MockGeocodingService implements GeocodingService {
  @override
  Future<GeoResult?> geocodeAddress(String address) async {
    // 有料APIは呼ばず、京都周辺のモック座標を返す。
    if (address.contains('京都')) {
      return GeoResult(
        latitude: 35.0116,
        longitude: 135.7681,
        formattedAddress: address,
      );
    }
    return GeoResult(
      latitude: 35.6812,
      longitude: 139.7671,
      formattedAddress: address,
    );
  }

  @override
  Future<GeoResult?> reverseGeocode(double latitude, double longitude) async {
    return GeoResult(
      latitude: latitude,
      longitude: longitude,
      formattedAddress: '緯度 $latitude / 経度 $longitude',
    );
  }
}

abstract class PlaceSearchService {
  Future<List<PlaceSearchHit>> searchByName(
    String query, {
    String? nearAddress,
  });
  Future<List<PlaceSearchHit>> searchNearby({
    required double latitude,
    required double longitude,
    String? keyword,
  });
}

class PlaceSearchHit {
  const PlaceSearchHit({
    required this.name,
    this.address,
    this.latitude,
    this.longitude,
    this.externalPlaceId,
  });

  final String name;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? externalPlaceId;
}

class MockPlaceSearchService implements PlaceSearchService {
  static const _catalog = [
    PlaceSearchHit(
      name: 'イノダコーヒ 本店',
      address: '京都府京都市中京区道祐町140',
      latitude: 35.0075,
      longitude: 135.7615,
      externalPlaceId: 'mock-inoda-main',
    ),
    PlaceSearchHit(
      name: 'イノダコーヒ 三条支店',
      address: '京都府京都市中京区三条通河原町東入ル',
      latitude: 35.0091,
      longitude: 135.7694,
      externalPlaceId: 'mock-inoda-sanjo',
    ),
    PlaceSearchHit(
      name: '喫茶ソワレ',
      address: '京都府京都市下京区西木屋町通四条上る真町95',
      latitude: 34.9995,
      longitude: 135.7681,
      externalPlaceId: 'mock-soire',
    ),
  ];

  @override
  Future<List<PlaceSearchHit>> searchByName(
    String query, {
    String? nearAddress,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _catalog
        .where(
          (h) =>
              h.name.toLowerCase().contains(q) ||
              (h.address ?? '').contains(query),
        )
        .toList();
  }

  @override
  Future<List<PlaceSearchHit>> searchNearby({
    required double latitude,
    required double longitude,
    String? keyword,
  }) async {
    return _catalog;
  }
}

abstract class PostAnalysisService {
  Future<PostAnalysisResponse> analyze(PostAnalysisRequest request);
}

/// ローカルモック。実AIはバックエンドEdge Function経由で接続する。
class MockPostAnalysisService implements PostAnalysisService {
  @override
  Future<PostAnalysisResponse> analyze(PostAnalysisRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (request.url != null && request.url!.contains('fail')) {
      throw StateError('解析APIに接続できませんでした');
    }
    final text = '${request.text ?? ''} ${request.url ?? ''}';
    if (text.contains('京都') || text.contains('instagram')) {
      return PostAnalysisResponse(
        sourcePostId: request.sourcePostId,
        rawSummary: 'モック解析: 投稿文から複数候補を抽出',
        candidates: [
          ExtractionCandidate(
            name: '喫茶ソワレ',
            address: '京都府京都市下京区西木屋町通四条上る真町95',
            reason: '青い照明の店内とゼリーポンチが印象的',
            evidenceSummary: '住所の取得元：画像 / 店名の取得元：投稿文',
            confidencePercent: 96,
            match: PlaceMatchConfidence.high,
            latitude: 34.9995,
            longitude: 135.7681,
            mapPinX: 0.3,
            mapPinY: 0.35,
          ),
          ExtractionCandidate(
            name: '鍵善良房 四条本店',
            address: '京都府京都市東山区祇園町北側264',
            reason: '名物のくずきり',
            evidenceSummary: '住所の取得元：画像3枚目',
            confidencePercent: 93,
            match: PlaceMatchConfidence.high,
            latitude: 35.0036,
            longitude: 135.7784,
            mapPinX: 0.55,
            mapPinY: 0.48,
          ),
          ExtractionCandidate(
            name: 'イノダコーヒ 本店',
            address: '京都府京都市中京区道祐町140',
            reason: '京の朝食が紹介されていた',
            evidenceSummary: '住所の取得元：投稿文 / 店名検索と不一致の可能性',
            confidencePercent: 78,
            match: PlaceMatchConfidence.needsReview,
            hasAddressMismatch: true,
            postAddress: '京都府京都市中京区道祐町140',
            searchCandidateName: 'イノダコーヒ 三条支店',
            searchCandidateAddress: '京都府京都市中京区三条通河原町東入ル',
            latitude: 35.0075,
            longitude: 135.7615,
            mapPinX: 0.42,
            mapPinY: 0.62,
          ),
        ],
      );
    }
    return PostAnalysisResponse(
      sourcePostId: request.sourcePostId,
      rawSummary: 'モック解析: 候補を1件抽出',
      candidates: [
        ExtractionCandidate(
          name: request.text?.trim().isNotEmpty == true
              ? request.text!.trim().split('\n').first
              : '共有された場所',
          address: null,
          reason: 'URLまたはテキストから暫定抽出',
          match: PlaceMatchConfidence.needsReview,
          evidenceSummary: '詳細住所は未確定。手動確認が必要です',
        ),
      ],
    );
  }
}
