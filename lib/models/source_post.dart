import '../core/ids.dart';
import 'enums.dart';

class SourcePost {
  SourcePost({
    String? id,
    this.url,
    this.service,
    this.title,
    this.body,
    this.userMemo,
    List<String>? userCategories,
    this.userCategoriesSet = false,
    List<String>? imagePaths,
    DateTime? receivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? newId(),
       userCategories = userCategories ?? const [],
       imagePaths = imagePaths ?? const [],
       receivedAt = receivedAt ?? DateTime.now(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String? url;
  String? service;
  String? title;
  String? body;
  String? userMemo;
  List<String> userCategories;
  bool userCategoriesSet;
  List<String> imagePaths;
  DateTime receivedAt;
  DateTime createdAt;
  DateTime updatedAt;

  SourcePost copyWith({
    String? url,
    String? service,
    String? title,
    String? body,
    String? userMemo,
    bool clearUserMemo = false,
    List<String>? userCategories,
    bool? userCategoriesSet,
    List<String>? imagePaths,
    DateTime? updatedAt,
  }) {
    return SourcePost(
      id: id,
      url: url ?? this.url,
      service: service ?? this.service,
      title: title ?? this.title,
      body: body ?? this.body,
      userMemo: clearUserMemo ? null : userMemo ?? this.userMemo,
      userCategories: userCategories ?? this.userCategories,
      userCategoriesSet: userCategoriesSet ?? this.userCategoriesSet,
      imagePaths: imagePaths ?? this.imagePaths,
      receivedAt: receivedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'service': service,
    'title': title,
    'body': body,
    'userMemo': userMemo,
    'userCategories': userCategories,
    'userCategoriesSet': userCategoriesSet,
    'imagePaths': imagePaths,
    'receivedAt': receivedAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory SourcePost.fromJson(Map<String, dynamic> json) => SourcePost(
    id: json['id'] as String,
    url: json['url'] as String?,
    service: json['service'] as String?,
    title: json['title'] as String?,
    body: json['body'] as String?,
    userMemo: json['userMemo'] as String?,
    userCategories: ((json['userCategories'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    userCategoriesSet: json['userCategoriesSet'] as bool? ?? false,
    imagePaths: ((json['imagePaths'] as List?) ?? const [])
        .map((e) => e as String)
        .toList(),
    receivedAt: DateTime.parse(json['receivedAt'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

class PlaceSource {
  PlaceSource({
    String? id,
    required this.placeId,
    required this.sourcePostId,
    DateTime? linkedAt,
  }) : id = id ?? newId(),
       linkedAt = linkedAt ?? DateTime.now();

  final String id;
  final String placeId;
  final String sourcePostId;
  final DateTime linkedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'placeId': placeId,
    'sourcePostId': sourcePostId,
    'linkedAt': linkedAt.toIso8601String(),
  };

  factory PlaceSource.fromJson(Map<String, dynamic> json) => PlaceSource(
    id: json['id'] as String,
    placeId: json['placeId'] as String,
    sourcePostId: json['sourcePostId'] as String,
    linkedAt: DateTime.parse(json['linkedAt'] as String),
  );
}

class AnalysisJob {
  AnalysisJob({
    String? id,
    required this.sourcePostId,
    this.status = AnalysisJobStatus.pending,
    this.errorMessage,
    this.resultJson,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String sourcePostId;
  AnalysisJobStatus status;
  String? errorMessage;
  String? resultJson;
  DateTime createdAt;
  DateTime updatedAt;

  AnalysisJob copyWith({
    AnalysisJobStatus? status,
    String? errorMessage,
    String? resultJson,
    DateTime? updatedAt,
  }) {
    return AnalysisJob(
      id: id,
      sourcePostId: sourcePostId,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      resultJson: resultJson ?? this.resultJson,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourcePostId': sourcePostId,
    'status': status.name,
    'errorMessage': errorMessage,
    'resultJson': resultJson,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory AnalysisJob.fromJson(Map<String, dynamic> json) => AnalysisJob(
    id: json['id'] as String,
    sourcePostId: json['sourcePostId'] as String,
    status: AnalysisJobStatus.fromName(json['status'] as String?),
    errorMessage: json['errorMessage'] as String?,
    resultJson: json['resultJson'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}
