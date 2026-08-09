import 'package:flutter/material.dart';

import '../core/ids.dart';

class PinMap {
  PinMap({
    String? id,
    required this.name,
    this.description = '',
    this.icon = '📍',
    this.themeColorValue = 0xFFE8F1EC,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isPublic = false,
    this.allowsCollaboration = false,
    this.lastLatitude,
    this.lastLongitude,
    this.lastZoom,
    this.sortSettingsJson,
    this.filterSettingsJson,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String name;
  String description;
  String icon;
  int themeColorValue;
  DateTime createdAt;
  DateTime updatedAt;
  bool isPublic;
  bool allowsCollaboration;
  double? lastLatitude;
  double? lastLongitude;
  double? lastZoom;
  String? sortSettingsJson;
  String? filterSettingsJson;

  Color get themeColor => Color(themeColorValue);

  PinMap copyWith({
    String? name,
    String? description,
    String? icon,
    int? themeColorValue,
    DateTime? updatedAt,
    bool? isPublic,
    bool? allowsCollaboration,
    double? lastLatitude,
    double? lastLongitude,
    double? lastZoom,
    String? sortSettingsJson,
    String? filterSettingsJson,
  }) {
    return PinMap(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      themeColorValue: themeColorValue ?? this.themeColorValue,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPublic: isPublic ?? this.isPublic,
      allowsCollaboration: allowsCollaboration ?? this.allowsCollaboration,
      lastLatitude: lastLatitude ?? this.lastLatitude,
      lastLongitude: lastLongitude ?? this.lastLongitude,
      lastZoom: lastZoom ?? this.lastZoom,
      sortSettingsJson: sortSettingsJson ?? this.sortSettingsJson,
      filterSettingsJson: filterSettingsJson ?? this.filterSettingsJson,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'icon': icon,
    'themeColorValue': themeColorValue,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'isPublic': isPublic,
    'allowsCollaboration': allowsCollaboration,
    'lastLatitude': lastLatitude,
    'lastLongitude': lastLongitude,
    'lastZoom': lastZoom,
    'sortSettingsJson': sortSettingsJson,
    'filterSettingsJson': filterSettingsJson,
  };

  factory PinMap.fromJson(Map<String, dynamic> json) => PinMap(
    id: json['id'] as String,
    name: json['name'] as String,
    description: (json['description'] as String?) ?? '',
    icon: (json['icon'] as String?) ?? '📍',
    themeColorValue: (json['themeColorValue'] as int?) ?? 0xFFE8F1EC,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    isPublic: (json['isPublic'] as bool?) ?? false,
    allowsCollaboration: (json['allowsCollaboration'] as bool?) ?? false,
    lastLatitude: (json['lastLatitude'] as num?)?.toDouble(),
    lastLongitude: (json['lastLongitude'] as num?)?.toDouble(),
    lastZoom: (json['lastZoom'] as num?)?.toDouble(),
    sortSettingsJson: json['sortSettingsJson'] as String?,
    filterSettingsJson: json['filterSettingsJson'] as String?,
  );
}
