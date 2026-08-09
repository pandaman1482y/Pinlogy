import '../core/ids.dart';
import 'enums.dart';

class Place {
  Place({
    String? id,
    required this.name,
    this.formalName,
    this.address,
    this.prefecture,
    this.city,
    this.area,
    this.nearestStation,
    this.building,
    this.floor,
    this.category,
    this.latitude,
    this.longitude,
    this.externalPlaceId,
    this.coverImagePath,
    this.saveReason,
    this.userMemo,
    this.recommendedItems,
    this.notesFromPost,
    this.extractedAddress,
    this.evidenceSummary,
    this.confidencePercent,
    this.openingTimeMinutes,
    this.closingTimeMinutes,
    this.closedWeekdays = const [],
    this.visitStatus = VisitStatus.wantToGo,
    this.visitCount = 0,
    this.firstVisitedAt,
    this.lastVisitedAt,
    this.mapPinX,
    this.mapPinY,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String name;
  String? formalName;
  String? address;
  String? prefecture;
  String? city;
  String? area;
  String? nearestStation;
  String? building;
  String? floor;
  String? category;
  double? latitude;
  double? longitude;
  String? externalPlaceId;

  /// ユーザーが選んだ端末内の代表写真。クラウド同期時も端末側を優先する。
  String? coverImagePath;
  String? saveReason;
  String? userMemo;
  String? recommendedItems;
  String? notesFromPost;
  String? extractedAddress;
  String? evidenceSummary;
  int? confidencePercent;

  /// 営業開始・終了（0:00からの分）。日をまたぐ営業時間にも対応する。
  int? openingTimeMinutes;
  int? closingTimeMinutes;
  List<int> closedWeekdays;
  VisitStatus visitStatus;
  int visitCount;
  DateTime? firstVisitedAt;
  DateTime? lastVisitedAt;

  /// モック地図上の相対位置 (0-1)。実地図API接続前の表示用。
  double? mapPinX;
  double? mapPinY;
  DateTime createdAt;
  DateTime updatedAt;

  bool get isVisited =>
      visitStatus == VisitStatus.visited ||
      visitStatus == VisitStatus.favorite ||
      visitCount > 0;

  bool get isFavorite => visitStatus == VisitStatus.favorite;

  bool isOpenAt(DateTime value) {
    if (openingTimeMinutes == null || closingTimeMinutes == null) return false;
    if (closedWeekdays.contains(value.weekday)) return false;
    final minute = value.hour * 60 + value.minute;
    if (openingTimeMinutes == closingTimeMinutes) return true;
    if (openingTimeMinutes! < closingTimeMinutes!) {
      return minute >= openingTimeMinutes! && minute < closingTimeMinutes!;
    }
    return minute >= openingTimeMinutes! || minute < closingTimeMinutes!;
  }

  String get openingHoursLabel {
    if (openingTimeMinutes == null || closingTimeMinutes == null) {
      return '営業時間未設定';
    }
    String time(int minutes) =>
        '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
    return '${time(openingTimeMinutes!)}〜${time(closingTimeMinutes!)}';
  }

  Place copyWith({
    String? name,
    String? formalName,
    String? address,
    String? prefecture,
    String? city,
    String? area,
    String? nearestStation,
    String? building,
    String? floor,
    String? category,
    double? latitude,
    double? longitude,
    String? externalPlaceId,
    String? coverImagePath,
    bool clearCoverImage = false,
    String? saveReason,
    String? userMemo,
    String? recommendedItems,
    String? notesFromPost,
    String? extractedAddress,
    String? evidenceSummary,
    int? confidencePercent,
    int? openingTimeMinutes,
    int? closingTimeMinutes,
    List<int>? closedWeekdays,
    VisitStatus? visitStatus,
    int? visitCount,
    DateTime? firstVisitedAt,
    DateTime? lastVisitedAt,
    double? mapPinX,
    double? mapPinY,
    DateTime? updatedAt,
  }) {
    return Place(
      id: id,
      name: name ?? this.name,
      formalName: formalName ?? this.formalName,
      address: address ?? this.address,
      prefecture: prefecture ?? this.prefecture,
      city: city ?? this.city,
      area: area ?? this.area,
      nearestStation: nearestStation ?? this.nearestStation,
      building: building ?? this.building,
      floor: floor ?? this.floor,
      category: category ?? this.category,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      externalPlaceId: externalPlaceId ?? this.externalPlaceId,
      coverImagePath: clearCoverImage
          ? null
          : coverImagePath ?? this.coverImagePath,
      saveReason: saveReason ?? this.saveReason,
      userMemo: userMemo ?? this.userMemo,
      recommendedItems: recommendedItems ?? this.recommendedItems,
      notesFromPost: notesFromPost ?? this.notesFromPost,
      extractedAddress: extractedAddress ?? this.extractedAddress,
      evidenceSummary: evidenceSummary ?? this.evidenceSummary,
      confidencePercent: confidencePercent ?? this.confidencePercent,
      openingTimeMinutes: openingTimeMinutes ?? this.openingTimeMinutes,
      closingTimeMinutes: closingTimeMinutes ?? this.closingTimeMinutes,
      closedWeekdays: closedWeekdays ?? this.closedWeekdays,
      visitStatus: visitStatus ?? this.visitStatus,
      visitCount: visitCount ?? this.visitCount,
      firstVisitedAt: firstVisitedAt ?? this.firstVisitedAt,
      lastVisitedAt: lastVisitedAt ?? this.lastVisitedAt,
      mapPinX: mapPinX ?? this.mapPinX,
      mapPinY: mapPinY ?? this.mapPinY,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'formalName': formalName,
    'address': address,
    'prefecture': prefecture,
    'city': city,
    'area': area,
    'nearestStation': nearestStation,
    'building': building,
    'floor': floor,
    'category': category,
    'latitude': latitude,
    'longitude': longitude,
    'externalPlaceId': externalPlaceId,
    'coverImagePath': coverImagePath,
    'saveReason': saveReason,
    'userMemo': userMemo,
    'recommendedItems': recommendedItems,
    'notesFromPost': notesFromPost,
    'extractedAddress': extractedAddress,
    'evidenceSummary': evidenceSummary,
    'confidencePercent': confidencePercent,
    'openingTimeMinutes': openingTimeMinutes,
    'closingTimeMinutes': closingTimeMinutes,
    'closedWeekdays': closedWeekdays,
    'visitStatus': visitStatus.name,
    'visitCount': visitCount,
    'firstVisitedAt': firstVisitedAt?.toIso8601String(),
    'lastVisitedAt': lastVisitedAt?.toIso8601String(),
    'mapPinX': mapPinX,
    'mapPinY': mapPinY,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Place.fromJson(Map<String, dynamic> json) => Place(
    id: json['id'] as String,
    name: json['name'] as String,
    formalName: json['formalName'] as String?,
    address: json['address'] as String?,
    prefecture: json['prefecture'] as String?,
    city: json['city'] as String?,
    area: json['area'] as String?,
    nearestStation: json['nearestStation'] as String?,
    building: json['building'] as String?,
    floor: json['floor'] as String?,
    category: json['category'] as String?,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    externalPlaceId: json['externalPlaceId'] as String?,
    coverImagePath: json['coverImagePath'] as String?,
    saveReason: json['saveReason'] as String?,
    userMemo: json['userMemo'] as String?,
    recommendedItems: json['recommendedItems'] as String?,
    notesFromPost: json['notesFromPost'] as String?,
    extractedAddress: json['extractedAddress'] as String?,
    evidenceSummary: json['evidenceSummary'] as String?,
    confidencePercent: json['confidencePercent'] as int?,
    openingTimeMinutes: json['openingTimeMinutes'] as int?,
    closingTimeMinutes: json['closingTimeMinutes'] as int?,
    closedWeekdays: ((json['closedWeekdays'] as List?) ?? const [])
        .whereType<num>()
        .map((value) => value.toInt())
        .toList(),
    visitStatus: VisitStatus.fromName(json['visitStatus'] as String?),
    visitCount: (json['visitCount'] as int?) ?? 0,
    firstVisitedAt: json['firstVisitedAt'] != null
        ? DateTime.parse(json['firstVisitedAt'] as String)
        : null,
    lastVisitedAt: json['lastVisitedAt'] != null
        ? DateTime.parse(json['lastVisitedAt'] as String)
        : null,
    mapPinX: (json['mapPinX'] as num?)?.toDouble(),
    mapPinY: (json['mapPinY'] as num?)?.toDouble(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}
