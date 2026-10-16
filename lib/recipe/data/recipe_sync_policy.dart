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
    clearCoverImage:
        edited.contains('coverImagePath') && existing.coverImagePath == null,
    coverImagePath: edited.contains('coverImagePath')
        ? existing.coverImagePath
        : incoming.coverImagePath ?? existing.coverImagePath,
    sourceUrl: incoming.sourceUrl ?? existing.sourceUrl,
    isFavorite: existing.isFavorite,
    isSaved: existing.isSaved || saveAutomatically,
    userEditedFields: edited,
    userNote: existing.userNote,
    lastMadeAt: existing.lastMadeAt,
    madeCount: existing.madeCount,
    createdAt: existing.createdAt,
    updatedAt: existing.updatedAt.isAfter(incoming.updatedAt)
        ? existing.updatedAt
        : incoming.updatedAt,
  );
}

/// Historical failures and unconfirmed old progress cards do not interrupt login.
/// Data and jobs are retained; new failures can still be retried in this session.
bool shouldShowImportInSession({
  required RecipeImportStatus status,
  required DateTime updatedAt,
  required DateTime sessionStartedAt,
  required bool remoteActive,
  required bool localTerminal,
}) {
  if (status == RecipeImportStatus.completed ||
      status == RecipeImportStatus.cancelled)
    return false;
  if (status == RecipeImportStatus.awaitingSelection) return true;
  if (remoteActive) return true;
  if (status == RecipeImportStatus.queued ||
      status == RecipeImportStatus.fetching ||
      status == RecipeImportStatus.analyzing) {
    return !localTerminal && !updatedAt.isBefore(sessionStartedAt);
  }
  return !updatedAt.isBefore(sessionStartedAt);
}
