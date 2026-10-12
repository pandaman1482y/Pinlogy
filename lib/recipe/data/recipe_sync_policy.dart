import '../models/recipe_models.dart';

bool shouldDownloadRecipeSnapshot({
  required DateTime? remoteUpdatedAt,
  required DateTime? knownUpdatedAt,
}) {
  if (remoteUpdatedAt == null) return false;
  return knownUpdatedAt == null || remoteUpdatedAt.isAfter(knownUpdatedAt);
}

/// AIの確定結果と端末上のレシピを統合する。
/// ユーザーが編集した項目だけを保護し、未編集の項目は最新解析へ更新する。
/// 旧版で工程0件のままparts編集扱いになったデータは自動修復する。
Recipe mergeAnalyzedRecipe({
  required Recipe existing,
  required Recipe incoming,
  required bool saveAutomatically,
}) {
  final edited = existing.userEditedFields;
  final keepEditedParts =
      edited.contains('parts') &&
      existing.allSteps.isNotEmpty &&
      incoming.allSteps.isNotEmpty;
  return incoming.copyWith(
    title: edited.contains('title') ? existing.title : incoming.title,
    description: edited.contains('description')
        ? existing.description
        : incoming.description,
    servings: edited.contains('servings')
        ? existing.servings
        : incoming.servings,
    servingUnit: edited.contains('servingUnit')
        ? existing.servingUnit
        : incoming.servingUnit,
    totalMinutes: edited.contains('totalMinutes')
        ? existing.totalMinutes
        : incoming.totalMinutes,
    category: edited.contains('category')
        ? existing.category
        : incoming.category,
    parts: keepEditedParts ? existing.parts : incoming.parts,
    evidence: keepEditedParts ? existing.evidence : incoming.evidence,
    coverImagePath: incoming.coverImagePath ?? existing.coverImagePath,
    sourceUrl: incoming.sourceUrl ?? existing.sourceUrl,
    isFavorite: existing.isFavorite,
    isSaved: existing.isSaved || saveAutomatically,
    userEditedFields: edited,
    userNote: existing.userNote,
    lastMadeAt: existing.lastMadeAt,
    madeCount: existing.madeCount,
    createdAt: existing.createdAt,
  );
}
