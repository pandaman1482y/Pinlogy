import '../core/ids.dart';

/// マップと場所の多対多中間テーブル。
class MapPlace {
  MapPlace({
    String? id,
    required this.mapId,
    required this.placeId,
    DateTime? addedAt,
  }) : id = id ?? newId(),
       addedAt = addedAt ?? DateTime.now();

  final String id;
  final String mapId;
  final String placeId;
  final DateTime addedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'mapId': mapId,
    'placeId': placeId,
    'addedAt': addedAt.toIso8601String(),
  };

  factory MapPlace.fromJson(Map<String, dynamic> json) => MapPlace(
    id: json['id'] as String,
    mapId: json['mapId'] as String,
    placeId: json['placeId'] as String,
    addedAt: DateTime.parse(json['addedAt'] as String),
  );
}
