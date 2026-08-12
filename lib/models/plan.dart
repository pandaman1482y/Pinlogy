import '../core/ids.dart';
import 'enums.dart';

/// 日付つき行程プラン。初期は空でよく、各フィールドは null を許容する。
class TripPlan {
  TripPlan({
    String? id,
    String? title,
    String? notes,
    this.startDate,
    this.startTimeMinutes = 9 * 60,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? newId(),
       title = (title == null || title.trim().isEmpty)
           ? '無題のプラン'
           : title.trim(),
       notes = notes ?? '',
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  String notes;
  DateTime? startDate;
  int startTimeMinutes;
  DateTime createdAt;
  DateTime updatedAt;

  TripPlan copyWith({
    String? title,
    String? notes,
    DateTime? startDate,
    bool clearStartDate = false,
    int? startTimeMinutes,
    DateTime? updatedAt,
  }) {
    return TripPlan(
      id: id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      startDate: clearStartDate ? null : (startDate ?? this.startDate),
      startTimeMinutes: startTimeMinutes ?? this.startTimeMinutes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'notes': notes,
    'startDate': startDate?.toIso8601String(),
    'startTimeMinutes': startTimeMinutes,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory TripPlan.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    final now = DateTime.now();
    return TripPlan(
      id: (json['id'] as String?)?.isNotEmpty == true
          ? json['id'] as String
          : null,
      title: json['title'] as String?,
      notes: json['notes'] as String?,
      startDate: parseDate(json['startDate']),
      startTimeMinutes: (json['startTimeMinutes'] as int?) ?? 9 * 60,
      createdAt: parseDate(json['createdAt']) ?? now,
      updatedAt: parseDate(json['updatedAt']) ?? now,
    );
  }
}

/// 行程内の1地点。同じ日の中で [sortOrder] 順に並ぶ。
/// [dayDate] 未設定の地点は「日付未定」として扱う。
/// [transitToNext] / [transitMinutes] は次の地点までの移動。
class PlanStop {
  PlanStop({
    String? id,
    required this.planId,
    required this.placeId,
    DateTime? dayDate,
    this.sortOrder = 0,
    this.stayMinutes,
    this.transitToNext,
    this.transitMinutes,
    this.transitTimeIsManual = false,
    this.transitBufferMinutes = 0,
    this.reservationTimeMinutes,
    this.arrivalDeadlineMinutes,
    this.note,
    DateTime? createdAt,
  }) : id = id ?? newId(),
       dayDate = dayDate == null ? null : dateOnly(dayDate),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String planId;
  String placeId;
  DateTime? dayDate;
  int sortOrder;
  int? stayMinutes;
  TransitMode? transitToNext;
  int? transitMinutes;
  bool transitTimeIsManual;
  int transitBufferMinutes;
  int? reservationTimeMinutes;
  int? arrivalDeadlineMinutes;
  String? note;
  DateTime createdAt;

  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  PlanStop copyWith({
    String? placeId,
    DateTime? dayDate,
    bool clearDayDate = false,
    int? sortOrder,
    int? stayMinutes,
    bool clearStayMinutes = false,
    TransitMode? transitToNext,
    bool clearTransitToNext = false,
    int? transitMinutes,
    bool clearTransitMinutes = false,
    bool? transitTimeIsManual,
    int? transitBufferMinutes,
    int? reservationTimeMinutes,
    bool clearReservationTime = false,
    int? arrivalDeadlineMinutes,
    bool clearArrivalDeadline = false,
    String? note,
    bool clearNote = false,
  }) {
    return PlanStop(
      id: id,
      planId: planId,
      placeId: placeId ?? this.placeId,
      dayDate: clearDayDate ? null : (dayDate ?? this.dayDate),
      sortOrder: sortOrder ?? this.sortOrder,
      stayMinutes: clearStayMinutes ? null : (stayMinutes ?? this.stayMinutes),
      transitToNext: clearTransitToNext
          ? null
          : (transitToNext ?? this.transitToNext),
      transitMinutes: clearTransitMinutes
          ? null
          : (transitMinutes ?? this.transitMinutes),
      transitTimeIsManual:
          transitTimeIsManual ?? this.transitTimeIsManual,
      transitBufferMinutes: transitBufferMinutes ?? this.transitBufferMinutes,
      reservationTimeMinutes: clearReservationTime
          ? null
          : (reservationTimeMinutes ?? this.reservationTimeMinutes),
      arrivalDeadlineMinutes: clearArrivalDeadline
          ? null
          : (arrivalDeadlineMinutes ?? this.arrivalDeadlineMinutes),
      note: clearNote ? null : (note ?? this.note),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'planId': planId,
    'placeId': placeId,
    'dayDate': dayDate?.toIso8601String(),
    'sortOrder': sortOrder,
    'stayMinutes': stayMinutes,
    'transitToNext': transitToNext?.name,
    'transitMinutes': transitMinutes,
    'transitTimeIsManual': transitTimeIsManual,
    'transitBufferMinutes': transitBufferMinutes,
    'reservationTimeMinutes': reservationTimeMinutes,
    'arrivalDeadlineMinutes': arrivalDeadlineMinutes,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PlanStop.fromJson(Map<String, dynamic> json) {
    final planId = json['planId'] as String?;
    final placeId = json['placeId'] as String?;
    if (planId == null ||
        planId.isEmpty ||
        placeId == null ||
        placeId.isEmpty) {
      throw ArgumentError('PlanStop に planId / placeId がありません');
    }

    DateTime? parseDate(Object? value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    return PlanStop(
      id: (json['id'] as String?)?.isNotEmpty == true
          ? json['id'] as String
          : null,
      planId: planId,
      placeId: placeId,
      dayDate: parseDate(json['dayDate']),
      sortOrder: (json['sortOrder'] as int?) ?? 0,
      stayMinutes: json['stayMinutes'] as int?,
      transitToNext: TransitMode.fromName(json['transitToNext'] as String?),
      transitMinutes: json['transitMinutes'] as int?,
      transitTimeIsManual: json['transitTimeIsManual'] as bool? ?? false,
      transitBufferMinutes: (json['transitBufferMinutes'] as int?) ?? 0,
      reservationTimeMinutes: json['reservationTimeMinutes'] as int?,
      arrivalDeadlineMinutes: json['arrivalDeadlineMinutes'] as int?,
      note: json['note'] as String?,
      createdAt: parseDate(json['createdAt']),
    );
  }
}
