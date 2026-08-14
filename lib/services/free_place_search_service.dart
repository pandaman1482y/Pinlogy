import 'dart:convert';

import 'package:http/http.dart' as http;

import 'location_services.dart';

/// 国土地理院の住所検索 + OpenStreetMap Nominatim（無料・キー不要）。
class FreePlaceSearchService implements PlaceSearchService {
  FreePlaceSearchService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  DateTime? _lastNominatimRequest;
  final Map<String, http.Response> _nominatimCache = {};

  static const _gsiSearch =
      'https://msearch.gsi.go.jp/address-search/AddressSearch';
  static const _nominatimSearch = 'https://nominatim.openstreetmap.org/search';
  static const _userAgent = 'Pinlogy/1.0 (support@pinlogy.app)';

  @override
  Future<List<PlaceSearchHit>> searchByName(
    String query, {
    String? nearAddress,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final area = nearAddress?.trim() ?? '';
    final enrichedQuery = area.isEmpty || q.contains(area) ? q : '$q $area';

    final results = await Future.wait([
      _searchGsi(enrichedQuery),
      _searchNominatim(enrichedQuery),
    ]);
    final merged = rankAndMerge(q, results[1], results[0], nearAddress: area);
    if (merged.isNotEmpty || enrichedQuery == q) return merged;

    final fallback = await Future.wait([_searchGsi(q), _searchNominatim(q)]);
    return rankAndMerge(q, fallback[1], fallback[0], nearAddress: area);
  }

  @override
  Future<List<PlaceSearchHit>> searchNearby({
    required double latitude,
    required double longitude,
    String? keyword,
  }) async {
    final q = (keyword ?? '').trim();
    if (q.isNotEmpty) {
      return searchByName(q);
    }

    final reverseUri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': '$latitude',
      'lon': '$longitude',
      'zoom': '18',
      'addressdetails': '1',
    });

    try {
      final response = await _getNominatim(reverseUri);
      if (response.statusCode != 200) return const [];
      final map = jsonDecode(response.body);
      if (map is! Map<String, dynamic>) return const [];
      final hit = _hitFromNominatim(map);
      return hit == null ? const [] : [hit];
    } catch (_) {
      return const [];
    }
  }

  Future<List<PlaceSearchHit>> _searchGsi(String query) async {
    final uri = Uri.parse(_gsiSearch).replace(queryParameters: {'q': query});
    try {
      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return const [];
      return parseGsiResponse(response.body);
    } catch (_) {
      return const [];
    }
  }

  Future<List<PlaceSearchHit>> _searchNominatim(String query) async {
    final uri = Uri.parse(_nominatimSearch).replace(
      queryParameters: {
        'q': query,
        'format': 'jsonv2',
        'countrycodes': 'jp',
        'limit': '12',
        'addressdetails': '1',
      },
    );
    try {
      final response = await _getNominatim(uri);
      if (response.statusCode != 200) return const [];
      return parseNominatimResponse(response.body);
    } catch (_) {
      return const [];
    }
  }

  Future<http.Response> _getNominatim(Uri uri) async {
    final key = uri.toString();
    final cached = _nominatimCache[key];
    if (cached != null) return cached;
    final last = _lastNominatimRequest;
    if (last != null) {
      final wait = const Duration(seconds: 1) - DateTime.now().difference(last);
      if (!wait.isNegative) await Future<void>.delayed(wait);
    }
    _lastNominatimRequest = DateTime.now();
    final response = await _client
        .get(
          uri,
          headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == 200) {
      if (_nominatimCache.length >= 100) {
        _nominatimCache.remove(_nominatimCache.keys.first);
      }
      _nominatimCache[key] = response;
    }
    return response;
  }

  static List<PlaceSearchHit> parseGsiResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];
    final hits = <PlaceSearchHit>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final geometry = map['geometry'];
      final properties = map['properties'];
      if (geometry is! Map || properties is! Map) continue;
      final coords = geometry['coordinates'];
      if (coords is! List || coords.length < 2) continue;
      final lng = (coords[0] as num).toDouble();
      final lat = (coords[1] as num).toDouble();
      final title = (properties['title'] as String?)?.trim();
      if (title == null || title.isEmpty) continue;
      hits.add(
        PlaceSearchHit(
          name: title,
          address: title,
          latitude: lat,
          longitude: lng,
          externalPlaceId: 'gsi:${properties['addressCode'] ?? title}',
        ),
      );
    }
    return hits;
  }

  static List<PlaceSearchHit> parseNominatimResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];
    final hits = <PlaceSearchHit>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final hit = _hitFromNominatim(Map<String, dynamic>.from(item));
      if (hit != null) hits.add(hit);
    }
    return hits;
  }

  static PlaceSearchHit? _hitFromNominatim(Map<String, dynamic> map) {
    final lat = double.tryParse('${map['lat']}');
    final lon = double.tryParse('${map['lon']}');
    if (lat == null || lon == null) return null;

    final display = (map['display_name'] as String?)?.trim();
    final name = (map['name'] as String?)?.trim();
    final label = (name != null && name.isNotEmpty)
        ? name
        : (display ?? '').split(',').first.trim();
    if (label.isEmpty) return null;

    return PlaceSearchHit(
      name: label,
      address: display ?? label,
      latitude: lat,
      longitude: lon,
      externalPlaceId: 'osm:${map['osm_type'] ?? ''}:${map['osm_id'] ?? ''}',
    );
  }

  static List<PlaceSearchHit> rankAndMerge(
    String query,
    List<PlaceSearchHit> primary,
    List<PlaceSearchHit> secondary, {
    String? nearAddress,
  }) {
    final merged = <PlaceSearchHit>[];
    bool isNear(PlaceSearchHit a, PlaceSearchHit b) {
      if (a.latitude == null ||
          a.longitude == null ||
          b.latitude == null ||
          b.longitude == null) {
        return a.name == b.name;
      }
      return (a.latitude! - b.latitude!).abs() < 0.0008 &&
          (a.longitude! - b.longitude!).abs() < 0.0008;
    }

    void addAll(List<PlaceSearchHit> source) {
      for (final hit in source) {
        if (merged.any((e) => isNear(e, hit) || e.name == hit.name)) continue;
        merged.add(hit);
      }
    }

    addAll(primary);
    addAll(secondary);
    final normalizedQuery = _normalizeSearchText(query);
    final area = _normalizeSearchText(nearAddress ?? '');
    int score(PlaceSearchHit hit) {
      final name = _normalizeSearchText(hit.name);
      final address = _normalizeSearchText(hit.address ?? '');
      var value = 0;
      if (name == normalizedQuery) {
        value += 1000;
      } else if (name.startsWith(normalizedQuery)) {
        value += 820;
      } else if (name.contains(normalizedQuery)) {
        value += 700;
      } else if (address.contains(normalizedQuery)) {
        value += 240;
      }
      if (area.isNotEmpty && address.contains(area)) value += 120;
      if (name == address) value -= 280;
      if (RegExp(r'^(?:〒?\d{3}-?\d{4})?[東京都道府県]').hasMatch(hit.name)) {
        value -= 220;
      }
      return value;
    }

    final originalOrder = {
      for (var i = 0; i < merged.length; i++) merged[i]: i,
    };
    merged.sort((a, b) {
      final byScore = score(b).compareTo(score(a));
      if (byScore != 0) return byScore;
      return originalOrder[a]!.compareTo(originalOrder[b]!);
    });
    return merged.take(20).toList(growable: false);
  }

  static String _normalizeSearchText(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s　・·\-_－]'), '');
}

/// 国土地理院ベースのジオコーディング（無料・キー不要）。
class GsiGeocodingService implements GeocodingService {
  GsiGeocodingService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<GeoResult?> geocodeAddress(String address) async {
    final hits = await FreePlaceSearchService(client: _client)
        .searchByName(address);
    if (hits.isEmpty) return null;
    final first = hits.first;
    if (first.latitude == null || first.longitude == null) return null;
    return GeoResult(
      latitude: first.latitude!,
      longitude: first.longitude!,
      formattedAddress: first.address ?? first.name,
    );
  }

  @override
  Future<GeoResult?> reverseGeocode(double latitude, double longitude) async {
    final uri = Uri.https(
      'mreversegeocoder.gsi.go.jp',
      '/reverse-geocoder/LonLatToAddress',
      {'lat': '$latitude', 'lon': '$longitude'},
    );
    try {
      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return GeoResult(
          latitude: latitude,
          longitude: longitude,
          formattedAddress: '緯度 $latitude / 経度 $longitude',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return GeoResult(latitude: latitude, longitude: longitude);
      }
      final result = decoded['result'];
      String? label;
      if (result is Map) {
        final muni = result['muniName'] as String? ?? '';
        final lv = result['lv01Nm'] as String? ?? '';
        label = '$muni$lv'.trim();
      }
      return GeoResult(
        latitude: latitude,
        longitude: longitude,
        formattedAddress: (label == null || label.isEmpty) ? null : label,
      );
    } catch (_) {
      return GeoResult(
        latitude: latitude,
        longitude: longitude,
        formattedAddress: '緯度 $latitude / 経度 $longitude',
      );
    }
  }
}
