enum VisitStatus {
  wantToGo,
  visited,
  favorite,
  onHold;

  String get label => switch (this) {
    VisitStatus.wantToGo => '行きたい',
    VisitStatus.visited => '訪問済み',
    VisitStatus.favorite => 'お気に入り',
    VisitStatus.onHold => '保留',
  };

  static VisitStatus fromName(String? name) {
    return VisitStatus.values.firstWhere(
      (v) => v.name == name,
      orElse: () => VisitStatus.wantToGo,
    );
  }
}

enum AnalysisJobStatus {
  pending,
  processing,
  completed,
  failed,
  cancelled;

  String get label => switch (this) {
    AnalysisJobStatus.pending => '待機中',
    AnalysisJobStatus.processing => '解析中…',
    AnalysisJobStatus.completed => '完了',
    AnalysisJobStatus.failed => '失敗',
    AnalysisJobStatus.cancelled => 'キャンセル',
  };

  static AnalysisJobStatus fromName(String? name) {
    return AnalysisJobStatus.values.firstWhere(
      (v) => v.name == name,
      orElse: () => AnalysisJobStatus.pending,
    );
  }
}

enum PlaceMatchConfidence {
  high,
  needsReview,
  unresolved;

  String get label => switch (this) {
    PlaceMatchConfidence.high => '住所・店名の一致を確認済み',
    PlaceMatchConfidence.needsReview => '住所または支店の確認が必要',
    PlaceMatchConfidence.unresolved => '場所を特定できていません',
  };

  static PlaceMatchConfidence fromName(String? name) {
    return PlaceMatchConfidence.values.firstWhere(
      (v) => v.name == name,
      orElse: () => PlaceMatchConfidence.needsReview,
    );
  }
}

enum PlaceSortOption {
  registeredDesc,
  updatedDesc,
  visitCountDesc,
  lastVisitedDesc,
  nameAsc,
  nearest;

  String get label => switch (this) {
    PlaceSortOption.registeredDesc => '登録日時',
    PlaceSortOption.updatedDesc => '更新日時',
    PlaceSortOption.visitCountDesc => '訪問回数',
    PlaceSortOption.lastVisitedDesc => '最終訪問日',
    PlaceSortOption.nameAsc => '名前',
    PlaceSortOption.nearest => '現在地から近い',
  };
}

enum PlaceFilterOption {
  all,
  unvisited,
  visited,
  favorite,
  nearby,
  openNow;

  String get label => switch (this) {
    PlaceFilterOption.all => 'すべて',
    PlaceFilterOption.unvisited => '未訪問',
    PlaceFilterOption.visited => '訪問済み',
    PlaceFilterOption.favorite => 'お気に入り',
    PlaceFilterOption.nearby => '近く',
    PlaceFilterOption.openNow => '今行ける',
  };
}

enum TransitMode {
  walk,
  train,
  car,
  bus,
  bike,
  other;

  String get label => switch (this) {
    TransitMode.walk => '徒歩',
    TransitMode.train => '電車',
    TransitMode.car => '車',
    TransitMode.bus => 'バス',
    TransitMode.bike => '自転車',
    TransitMode.other => 'その他',
  };

  /// null 許可の fromName（未設定の区間用）。
  static TransitMode? fromName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final value in TransitMode.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
