import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../app/pinlogy_controller.dart';
import '../models/enums.dart';
import '../models/source_post.dart';
import '../services/notification_service.dart';
import '../services/share_receiver_service.dart';
import 'data/recipe_store.dart';
import 'models/recipe_models.dart';

class RecipeFilters {
  const RecipeFilters({
    this.category,
    this.cuisine,
    this.mainIngredient,
    this.method,
    this.maxMinutes,
    this.difficulty,
    this.sourceService,
    this.favoritesOnly = false,
    this.madeOnly = false,
    this.needsReviewOnly = false,
  });

  final String? category;
  final String? cuisine;
  final String? mainIngredient;
  final String? method;
  final int? maxMinutes;
  final String? difficulty;
  final String? sourceService;
  final bool favoritesOnly;
  final bool madeOnly;
  final bool needsReviewOnly;

  bool get isEmpty =>
      category == null &&
      cuisine == null &&
      mainIngredient == null &&
      method == null &&
      maxMinutes == null &&
      difficulty == null &&
      sourceService == null &&
      !favoritesOnly &&
      !madeOnly &&
      !needsReviewOnly;
}

/// Recipe-facing state layered on top of the proven Pinlogy share pipeline.
/// The legacy controller remains responsible for acquiring every SNS image and
/// completing durable background jobs. This controller only interprets and
/// presents those results as recipes.
class RecipeController extends ChangeNotifier {
  RecipeController({
    required this.legacy,
    RecipeStore? store,
  }) : store = store ?? SharedPreferencesRecipeStore();

  final PinlogyController legacy;
  final RecipeStore store;

  RecipeSnapshot snapshot = RecipeSnapshot();
  bool loading = true;
  String? loadError;
  bool _syncing = false;
  bool _syncAgain = false;
  bool _disposed = false;
  StreamSubscription<void>? _authSubscription;

  List<Recipe> get savedRecipes =>
      snapshot.recipes.where((recipe) => recipe.isSaved).toList();

  List<RecipeImport> get activeImports => snapshot.imports
      .where(
        (item) =>
            item.status != RecipeImportStatus.completed &&
            item.status != RecipeImportStatus.cancelled,
      )
      .toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  bool get notificationsEnabled =>
      PinlogyNotificationService.instance.enabled;
  bool get notificationsReady =>
      PinlogyNotificationService.instance.firebaseReady;

  Future<void> initialize() async {
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      snapshot = await store.load();
      legacy.addListener(_onLegacyChanged);
      if (legacy.cloud.isConfigured) {
        _authSubscription = legacy.cloud.watchAuthChanges().listen(
          (_) => _onAuthChanged(),
          onError: (_) {},
        );
      }
      await syncFromIntake();
    } catch (error) {
      loadError = 'レシピデータを読み込めませんでした: $error';
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _onLegacyChanged() {
    unawaited(syncFromIntake());
  }

  void _onAuthChanged() {
    if (_disposed) return;
    notifyListeners();
    if (legacy.cloud.user != null) unawaited(syncCloud());
  }

  Future<void> syncFromIntake() async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        await _performSync();
      } while (_syncAgain);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _performSync() async {
    final recipes = List<Recipe>.of(snapshot.recipes);
    final imports = List<RecipeImport>.of(snapshot.imports);
    var changed = false;

    for (final post in legacy.hub.snapshot.sourcePosts) {
      final job = legacy.jobForPost(post.id);
      final existingIndex = imports.indexWhere(
        (item) => item.sourcePostId == post.id,
      );
      final current = existingIndex < 0 ? null : imports[existingIndex];
      var status = _importStatus(job?.status);
      var message = job?.errorMessage;
      var recipeIds = current?.recipeIds ?? const <String>[];
      var requiresSelection = current?.requiresSelection ?? false;

      if (job?.status == AnalysisJobStatus.completed) {
        // Ignore completed place-analysis records left by the old Pinlogy UI.
        // New recipe responses always contain a `recipes` envelope, even when
        // extraction fails and the array itself is empty.
        if (!_hasRecipeEnvelope(job?.resultJson)) {
          if (current == null) continue;
          status = RecipeImportStatus.cancelled;
          message = '旧Pinlogyの取り込み履歴';
        }
        final parsed = _parseAnalysisResult(post, job?.resultJson);
        if (!_hasRecipeEnvelope(job?.resultJson)) {
          // The old record is intentionally kept out of the recipe list.
        } else if (parsed.isNotEmpty) {
          recipeIds = parsed.map((recipe) => recipe.id).toList();
          requiresSelection = parsed.length > 1;
          status = requiresSelection
              ? RecipeImportStatus.awaitingSelection
              : RecipeImportStatus.completed;
          message = requiresSelection
              ? '${parsed.length}件の料理を検出しました。保存するものを選んでください。'
              : null;
          for (var index = 0; index < parsed.length; index++) {
            final incoming = parsed[index];
            final recipeIndex = recipes.indexWhere(
              (item) => item.id == incoming.id,
            );
            if (recipeIndex < 0) {
              recipes.add(incoming.copyWith(isSaved: parsed.length == 1));
              changed = true;
              continue;
            }
            final existing = recipes[recipeIndex];
            if (existing.userEditedFields.isNotEmpty) {
              recipes[recipeIndex] = existing.copyWith(
                coverImagePath:
                    existing.coverImagePath ?? incoming.coverImagePath,
                sourceUrl: existing.sourceUrl ?? incoming.sourceUrl,
                status: incoming.status,
              );
            } else {
              recipes[recipeIndex] = incoming.copyWith(
                isFavorite: existing.isFavorite,
                isSaved: existing.isSaved || parsed.length == 1,
                userNote: existing.userNote,
                lastMadeAt: existing.lastMadeAt,
                madeCount: existing.madeCount,
                createdAt: existing.createdAt,
              );
            }
            changed = true;
          }
        } else {
          status = RecipeImportStatus.failed;
          message = '解析結果をレシピに変換できませんでした。再解析してください。';
        }
      }

      final next = RecipeImport(
        id: current?.id,
        sourcePostId: post.id,
        sourceUrl: post.url,
        sourceService: post.service,
        coverImagePath: _coverFor(post, null),
        status: status,
        message: message,
        recipeIds: recipeIds,
        requiresSelection: requiresSelection,
        createdAt: current?.createdAt ?? post.receivedAt,
        updatedAt: job?.updatedAt ?? post.updatedAt,
      );
      if (current == null) {
        imports.add(next);
        changed = true;
      } else if (jsonEncode(current.toJson()) != jsonEncode(next.toJson())) {
        imports[existingIndex] = next;
        changed = true;
      }
    }

    if (!changed) return;
    snapshot = _copySnapshot(recipes: recipes, imports: imports);
    await _persist();
  }

  RecipeImportStatus _importStatus(AnalysisJobStatus? status) => switch (status) {
    null => RecipeImportStatus.queued,
    AnalysisJobStatus.pending => RecipeImportStatus.queued,
    AnalysisJobStatus.processing => RecipeImportStatus.analyzing,
    AnalysisJobStatus.completed => RecipeImportStatus.completed,
    AnalysisJobStatus.failed => RecipeImportStatus.failed,
    AnalysisJobStatus.cancelled => RecipeImportStatus.cancelled,
  };

  List<Recipe> _parseAnalysisResult(SourcePost post, String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      final map = Map<String, dynamic>.from(decoded);
      final values = map['recipes'];
      if (values is! List) return const [];
      final output = <Recipe>[];
      for (var index = 0; index < values.length; index++) {
        final value = values[index];
        if (value is! Map) continue;
        final recipe = _recipeFromAnalysis(
          post,
          Map<String, dynamic>.from(value),
          index,
        );
        if (recipe != null) output.add(recipe);
      }
      return output;
    } catch (_) {
      return const [];
    }
  }

  bool _hasRecipeEnvelope(String? raw) {
    if (raw == null || raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map && decoded.containsKey('recipes');
    } catch (_) {
      return false;
    }
  }

  Recipe? _recipeFromAnalysis(
    SourcePost post,
    Map<String, dynamic> json,
    int recipeIndex,
  ) {
    final title = _text(json, 'title', 'name');
    if (title == null || title.length < 2) return null;
    final evidence = <RecipeEvidence>[];
    final rawEvidence = json['evidence'];
    if (rawEvidence is List) {
      for (var index = 0; index < rawEvidence.length; index++) {
        final item = rawEvidence[index];
        if (item is! Map) continue;
        final record = Map<String, dynamic>.from(item);
        final imageIndex = _integer(record, 'image_index', 'imageIndex');
        evidence.add(
          RecipeEvidence(
            id: '${post.id}_recipe_${recipeIndex}_evidence_$index',
            kind: EvidenceKind.fromName(
              _text(record, 'kind')?.replaceAll('author_comment', 'authorComment'),
            ),
            label: _text(record, 'label') ?? '根拠 ${index + 1}',
            imagePath: _coverFor(post, imageIndex),
            timestampSeconds: _integer(
              record,
              'timestamp_seconds',
              'timestampSeconds',
            ),
            excerpt: _text(record, 'excerpt'),
            confidencePercent: _integer(
              record,
              'confidence_percent',
              'confidencePercent',
            ),
          ),
        );
      }
    }

    final parts = <RecipePart>[];
    final rawParts = json['parts'];
    if (rawParts is List) {
      for (var partIndex = 0; partIndex < rawParts.length; partIndex++) {
        final item = rawParts[partIndex];
        if (item is! Map) continue;
        final record = Map<String, dynamic>.from(item);
        final ingredients = <RecipeIngredient>[];
        final rawIngredients = record['ingredients'];
        if (rawIngredients is List) {
          for (var ingredientIndex = 0;
              ingredientIndex < rawIngredients.length;
              ingredientIndex++) {
            final rawIngredient = rawIngredients[ingredientIndex];
            if (rawIngredient is! Map) continue;
            final ingredient = Map<String, dynamic>.from(rawIngredient);
            final name = _text(ingredient, 'name');
            if (name == null || name.isEmpty) continue;
            ingredients.add(
              RecipeIngredient(
                id: '${post.id}_r${recipeIndex}_p${partIndex}_i$ingredientIndex',
                name: name,
                amount: _number(ingredient, 'amount'),
                unit: _text(ingredient, 'unit'),
                originalText: _text(
                  ingredient,
                  'original_text',
                  'originalText',
                ),
                note: _text(ingredient, 'note'),
                scalable: ingredient['scalable'] as bool? ?? true,
                evidenceId: _evidenceId(
                  post.id,
                  recipeIndex,
                  _integer(ingredient, 'evidence_index', 'evidenceIndex'),
                  evidence.length,
                ),
                confidencePercent: _integer(
                  ingredient,
                  'confidence_percent',
                  'confidencePercent',
                ),
              ),
            );
          }
        }
        final steps = <RecipeStep>[];
        final rawSteps = record['steps'];
        if (rawSteps is List) {
          for (var stepIndex = 0; stepIndex < rawSteps.length; stepIndex++) {
            final rawStep = rawSteps[stepIndex];
            if (rawStep is! Map) continue;
            final step = Map<String, dynamic>.from(rawStep);
            final instruction = _text(step, 'instruction', 'text');
            if (instruction == null || instruction.isEmpty) continue;
            steps.add(
              RecipeStep(
                id: '${post.id}_r${recipeIndex}_p${partIndex}_s$stepIndex',
                order: _integer(step, 'order') ?? stepIndex + 1,
                instruction: instruction,
                durationSeconds: _integer(
                  step,
                  'duration_seconds',
                  'durationSeconds',
                ),
                evidenceId: _evidenceId(
                  post.id,
                  recipeIndex,
                  _integer(step, 'evidence_index', 'evidenceIndex'),
                  evidence.length,
                ),
                confidencePercent: _integer(
                  step,
                  'confidence_percent',
                  'confidencePercent',
                ),
              ),
            );
          }
        }
        if (ingredients.isNotEmpty || steps.isNotEmpty) {
          parts.add(
            RecipePart(
              id: '${post.id}_recipe_${recipeIndex}_part_$partIndex',
              name: _text(record, 'name') ?? (partIndex == 0 ? '本体' : 'パート ${partIndex + 1}'),
              ingredients: ingredients,
              steps: steps,
            ),
          );
        }
      }
    }

    final needsReview = _stringList(
      json['needs_review_fields'] ?? json['needsReviewFields'],
    );
    final warnings = _stringList(json['warnings']);
    final coverIndex = _integer(json, 'cover_image_index', 'coverImageIndex');
    final status = needsReview.isEmpty && parts.isNotEmpty
        ? RecipeStatus.ready
        : RecipeStatus.needsReview;
    final nutritionJson = json['nutrition'];
    final nutrition = nutritionJson is Map
        ? RecipeNutrition(
            calories: _integer(
              Map<String, dynamic>.from(nutritionJson),
              'calories',
            ),
            proteinGrams: _number(
              Map<String, dynamic>.from(nutritionJson),
              'protein_grams',
              'proteinGrams',
            ),
            fatGrams: _number(
              Map<String, dynamic>.from(nutritionJson),
              'fat_grams',
              'fatGrams',
            ),
            carbohydrateGrams: _number(
              Map<String, dynamic>.from(nutritionJson),
              'carbohydrate_grams',
              'carbohydrateGrams',
            ),
          )
        : null;

    return Recipe(
      id: '${post.id}_recipe_$recipeIndex',
      sourcePostId: post.id,
      title: title,
      description: _text(json, 'description', 'summary'),
      servings: _number(json, 'servings') ?? 2,
      totalMinutes: _integer(json, 'total_minutes', 'totalMinutes'),
      difficulty: _text(json, 'difficulty'),
      category: _text(json, 'category'),
      cuisine: _text(json, 'cuisine'),
      mainIngredient: _text(json, 'main_ingredient', 'mainIngredient'),
      method: _text(json, 'method'),
      parts: parts,
      evidence: evidence,
      coverImagePath: _coverFor(post, coverIndex),
      sourceUrl: post.url,
      sourceService: post.service,
      status: status,
      isSaved: false,
      allergens: _stringList(json['allergens']),
      warnings: warnings,
      needsReviewFields: needsReview,
      nutrition: nutrition,
      createdAt: post.receivedAt,
      updatedAt: DateTime.now(),
    );
  }

  String? _evidenceId(
    String sourcePostId,
    int recipeIndex,
    int? evidenceIndex,
    int count,
  ) {
    if (evidenceIndex == null || evidenceIndex < 0 || evidenceIndex >= count) {
      return null;
    }
    return '${sourcePostId}_recipe_${recipeIndex}_evidence_$evidenceIndex';
  }

  String? _coverFor(SourcePost post, int? index) {
    if (index != null && index >= 0 && index < post.imagePaths.length) {
      return post.imagePaths[index];
    }
    return post.displayThumbnailPath;
  }

  Future<void> saveSelectedRecipes(
    RecipeImport recipeImport,
    Set<String> selectedIds,
  ) async {
    final recipes = snapshot.recipes.map((recipe) {
      if (recipe.sourcePostId != recipeImport.sourcePostId) return recipe;
      return recipe.copyWith(isSaved: selectedIds.contains(recipe.id));
    }).toList();
    final imports = snapshot.imports.map((item) {
      if (item.id != recipeImport.id) return item;
      return item.copyWith(
        status: RecipeImportStatus.completed,
        message: selectedIds.isEmpty ? '保存せず完了しました。' : null,
        requiresSelection: false,
      );
    }).toList();
    snapshot = _copySnapshot(recipes: recipes, imports: imports);
    await _persist();
  }

  Future<void> retryImport(RecipeImport recipeImport) async {
    final job = legacy.jobForPost(recipeImport.sourcePostId);
    if (job == null) return;
    final imports = snapshot.imports.map((item) {
      if (item.id != recipeImport.id) return item;
      return item.copyWith(
        status: RecipeImportStatus.analyzing,
        message: '画像を再取得して解析しています…',
      );
    }).toList();
    snapshot = _copySnapshot(imports: imports);
    await _persist();
    await legacy.analysisRunner.retryJob(job.id);
    await syncFromIntake();
  }

  Future<void> cancelImport(RecipeImport recipeImport) async {
    final job = legacy.jobForPost(recipeImport.sourcePostId);
    if (job != null) {
      await legacy.analysisRunner.cancelJob(job.id);
    }
    final imports = snapshot.imports.map((item) {
      if (item.id != recipeImport.id) return item;
      return item.copyWith(status: RecipeImportStatus.cancelled);
    }).toList();
    snapshot = _copySnapshot(imports: imports);
    await _persist();
  }

  Recipe? recipeById(String id) =>
      snapshot.recipes.where((recipe) => recipe.id == id).firstOrNull;

  Recipe? existingRecipeForUrl(String rawUrl) {
    final normalized = _normalizedUrl(rawUrl);
    if (normalized == null) return null;
    return savedRecipes
        .where((recipe) => _normalizedUrl(recipe.sourceUrl) == normalized)
        .firstOrNull;
  }

  RecipeImport? existingImportForUrl(String rawUrl) {
    final normalized = _normalizedUrl(rawUrl);
    if (normalized == null) return null;
    return snapshot.imports
        .where((item) => _normalizedUrl(item.sourceUrl) == normalized)
        .firstOrNull;
  }

  Future<RecipeImport?> importFromUrl(String rawUrl) async {
    final normalized = _normalizedUrl(rawUrl);
    if (normalized == null) {
      throw const FormatException('InstagramまたはTikTokの投稿URLを入力してください');
    }
    final post = await legacy.shareIntake.ingest(
      SharedContent(url: normalized, title: '共有されたレシピ'),
    );
    await syncFromIntake();
    return snapshot.imports
        .where((item) => item.sourcePostId == post.id)
        .firstOrNull;
  }

  List<Recipe> recipesForImport(RecipeImport item) => snapshot.recipes
      .where((recipe) => item.recipeIds.contains(recipe.id))
      .toList();

  List<Recipe> relatedRecipes(Recipe recipe, {int limit = 6}) {
    final scored = savedRecipes
        .where((item) => item.id != recipe.id)
        .map((item) {
          var score = 0;
          if (item.category != null && item.category == recipe.category) {
            score += 2;
          }
          if (item.cuisine != null && item.cuisine == recipe.cuisine) {
            score += 2;
          }
          if (item.mainIngredient != null &&
              item.mainIngredient == recipe.mainIngredient) {
            score += 3;
          }
          if (item.method != null && item.method == recipe.method) score += 1;
          return (recipe: item, score: score);
        })
        .where((item) => item.score > 0)
        .toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0
            ? byScore
            : b.recipe.createdAt.compareTo(a.recipe.createdAt);
      });
    return scored.take(limit).map((item) => item.recipe).toList();
  }

  List<Recipe> filteredRecipes({
    String query = '',
    RecipeFilters filters = const RecipeFilters(),
  }) {
    final normalized = query.trim().toLowerCase();
    final tokens = normalized
        .split(RegExp(r'[\s　,，]+'))
        .where((value) => value.isNotEmpty)
        .toList();
    final values = savedRecipes.where((recipe) {
      final haystack = [
        recipe.title,
        recipe.description,
        recipe.category,
        recipe.cuisine,
        recipe.mainIngredient,
        recipe.method,
        recipe.sourceService,
        recipe.sourceAuthor,
        recipe.userNote,
        ...recipe.parts.map((part) => part.name),
        ...recipe.allIngredients.map((ingredient) => ingredient.name),
        ...recipe.allSteps.map((step) => step.instruction),
        ...recipe.evidence.map((item) => item.label),
        ...recipe.evidence.map((item) => item.excerpt),
      ].whereType<String>().join(' ').toLowerCase();
      if (tokens.any((token) => !haystack.contains(token))) return false;
      if (filters.category != null && recipe.category != filters.category) {
        return false;
      }
      if (filters.cuisine != null && recipe.cuisine != filters.cuisine) {
        return false;
      }
      if (filters.mainIngredient != null &&
          recipe.mainIngredient != filters.mainIngredient) {
        return false;
      }
      if (filters.method != null && recipe.method != filters.method) {
        return false;
      }
      if (filters.maxMinutes != null &&
          (recipe.totalMinutes == null ||
              recipe.totalMinutes! > filters.maxMinutes!)) {
        return false;
      }
      if (filters.difficulty != null &&
          recipe.difficulty != filters.difficulty) {
        return false;
      }
      if (filters.sourceService != null &&
          recipe.sourceService != filters.sourceService) {
        return false;
      }
      if (filters.favoritesOnly && !recipe.isFavorite) return false;
      if (filters.madeOnly && recipe.madeCount == 0) return false;
      if (filters.needsReviewOnly && recipe.status != RecipeStatus.needsReview) {
        return false;
      }
      return true;
    }).toList();
    _sort(values, snapshot.sort);
    return values;
  }

  void _sort(List<Recipe> values, RecipeSort sort) {
    switch (sort) {
      case RecipeSort.newest:
        values.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return;
      case RecipeSort.recentlyMade:
        values.sort(
          (a, b) => (b.lastMadeAt ?? DateTime(1970)).compareTo(
            a.lastMadeAt ?? DateTime(1970),
          ),
        );
        return;
      case RecipeSort.favorites:
        values.sort((a, b) {
          final favorite = (b.isFavorite ? 1 : 0) - (a.isFavorite ? 1 : 0);
          return favorite != 0 ? favorite : b.createdAt.compareTo(a.createdAt);
        });
        return;
      case RecipeSort.name:
        values.sort((a, b) => a.title.compareTo(b.title));
        return;
      case RecipeSort.shortest:
        values.sort(
          (a, b) => (a.totalMinutes ?? 9999).compareTo(b.totalMinutes ?? 9999),
        );
        return;
    }
  }

  Future<void> setSort(RecipeSort value) async {
    snapshot = _copySnapshot(sort: value);
    await _persist();
  }

  Future<void> saveRecipe(Recipe recipe) async {
    final values = List<Recipe>.of(snapshot.recipes);
    final index = values.indexWhere((item) => item.id == recipe.id);
    if (index < 0) {
      values.add(recipe);
    } else {
      values[index] = recipe;
    }
    snapshot = _copySnapshot(recipes: values);
    await _persist();
  }

  Future<void> addManualRecipe(Recipe recipe) =>
      saveRecipe(recipe.copyWith(isSaved: true, status: RecipeStatus.ready));

  Future<void> toggleFavorite(Recipe recipe) =>
      saveRecipe(recipe.copyWith(isFavorite: !recipe.isFavorite));

  Future<void> deleteRecipe(Recipe recipe) async {
    final recipes = snapshot.recipes.where((item) => item.id != recipe.id).toList();
    final collections = snapshot.collections
        .map(
          (item) => RecipeCollection(
            id: item.id,
            name: item.name,
            recipeIds: item.recipeIds.where((id) => id != recipe.id).toList(),
            isFavoriteCollection: item.isFavoriteCollection,
          ),
        )
        .toList();
    snapshot = _copySnapshot(recipes: recipes, collections: collections);
    await _persist();
  }

  Future<void> createCollection(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    snapshot = _copySnapshot(
      collections: [...snapshot.collections, RecipeCollection(name: trimmed)],
    );
    await _persist();
  }

  Future<void> toggleRecipeInCollection(
    Recipe recipe,
    RecipeCollection collection,
  ) async {
    final ids = List<String>.of(collection.recipeIds);
    ids.contains(recipe.id) ? ids.remove(recipe.id) : ids.add(recipe.id);
    final collections = snapshot.collections.map((item) {
      if (item.id != collection.id) return item;
      return RecipeCollection(
        id: item.id,
        name: item.name,
        recipeIds: ids,
        isFavoriteCollection: item.isFavoriteCollection,
      );
    }).toList();
    snapshot = _copySnapshot(collections: collections);
    await _persist();
  }

  Future<void> deleteCollection(RecipeCollection collection) async {
    snapshot = _copySnapshot(
      collections: snapshot.collections
          .where((item) => item.id != collection.id)
          .toList(),
    );
    await _persist();
  }

  Future<void> addToShoppingList(Recipe recipe, double multiplier) async {
    final items = List<ShoppingItem>.of(snapshot.shoppingItems);
    for (final ingredient in recipe.allIngredients) {
      final index = items.indexWhere(
        (item) => item.name.trim().toLowerCase() == ingredient.name.trim().toLowerCase(),
      );
      final quantity = ingredient.quantityFor(multiplier);
      if (index < 0) {
        items.add(
          ShoppingItem(
            name: ingredient.name,
            quantity: quantity,
            recipeIds: [recipe.id],
          ),
        );
      } else {
        final current = items[index];
        items[index] = ShoppingItem(
          id: current.id,
          name: current.name,
          quantity: [current.quantity, quantity]
              .where((value) => value.trim().isNotEmpty)
              .join(' + '),
          checked: current.checked,
          recipeIds: {...current.recipeIds, recipe.id}.toList(),
        );
      }
    }
    snapshot = _copySnapshot(shoppingItems: items);
    await _persist();
  }

  Future<void> toggleShoppingItem(ShoppingItem item) async {
    final items = snapshot.shoppingItems
        .map((value) => value.id == item.id ? value.copyWith(checked: !value.checked) : value)
        .toList();
    snapshot = _copySnapshot(shoppingItems: items);
    await _persist();
  }

  Future<void> addShoppingItem(String name, String quantity) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    snapshot = _copySnapshot(
      shoppingItems: [
        ...snapshot.shoppingItems,
        ShoppingItem(name: trimmed, quantity: quantity.trim()),
      ],
    );
    await _persist();
  }

  Future<void> clearPurchasedItems() async {
    snapshot = _copySnapshot(
      shoppingItems: snapshot.shoppingItems.where((item) => !item.checked).toList(),
    );
    await _persist();
  }

  Future<void> recordCooked(
    Recipe recipe, {
    int? rating,
    String? note,
    String? photoPath,
  }) async {
    final madeAt = DateTime.now();
    await saveRecipe(
      recipe.copyWith(lastMadeAt: madeAt, madeCount: recipe.madeCount + 1),
    );
    snapshot = _copySnapshot(
      cookingRecords: [
        ...snapshot.cookingRecords,
        CookingRecord(
          recipeId: recipe.id,
          madeAt: madeAt,
          rating: rating,
          note: note,
          photoPath: photoPath,
        ),
      ],
    );
    await _persist();
  }

  Future<void> submitFeedback(
    Recipe recipe,
    String type, {
    String? comment,
  }) async {
    snapshot = _copySnapshot(
      feedback: [
        ...snapshot.feedback,
        RecipeFeedback(recipeId: recipe.id, type: type, comment: comment),
      ],
    );
    await _persist();
  }

  Future<void> updateAllergySettings(AllergySettings value) async {
    snapshot = _copySnapshot(allergySettings: value);
    await _persist();
  }

  Future<bool> setNotificationsEnabled(bool value) async {
    final changed = await PinlogyNotificationService.instance.setEnabled(value);
    notifyListeners();
    return changed;
  }

  Future<void> syncCloud() async {
    final rawRemote = await legacy.cloud.loadRecipeSnapshot();
    if (rawRemote != null) {
      final remote = RecipeSnapshot.fromJson(rawRemote);
      snapshot = _mergeSnapshots(snapshot, remote);
      await _persist();
    }
    await legacy.cloud.saveRecipeSnapshot(snapshot.toJson());
  }

  Future<void> _persist() async {
    await store.save(snapshot);
    if (!_disposed) notifyListeners();
  }

  RecipeSnapshot _copySnapshot({
    List<Recipe>? recipes,
    List<RecipeImport>? imports,
    List<RecipeCollection>? collections,
    List<ShoppingItem>? shoppingItems,
    List<CookingRecord>? cookingRecords,
    List<RecipeFeedback>? feedback,
    AllergySettings? allergySettings,
    RecipeSort? sort,
  }) => RecipeSnapshot(
    recipes: recipes ?? snapshot.recipes,
    imports: imports ?? snapshot.imports,
    collections: collections ?? snapshot.collections,
    shoppingItems: shoppingItems ?? snapshot.shoppingItems,
    cookingRecords: cookingRecords ?? snapshot.cookingRecords,
    feedback: feedback ?? snapshot.feedback,
    allergySettings: allergySettings ?? snapshot.allergySettings,
    sort: sort ?? snapshot.sort,
  );

  @override
  void dispose() {
    _disposed = true;
    _authSubscription?.cancel();
    legacy.removeListener(_onLegacyChanged);
    super.dispose();
  }
}

String? _normalizedUrl(String? rawUrl) {
  final uri = Uri.tryParse(rawUrl?.trim() ?? '');
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  final supported = host == 'instagram.com' ||
      host.endsWith('.instagram.com') ||
      host == 'tiktok.com' ||
      host.endsWith('.tiktok.com');
  if (!supported) return null;
  return Uri(scheme: 'https', host: host, path: uri.path).toString();
}

RecipeSnapshot _mergeSnapshots(RecipeSnapshot local, RecipeSnapshot remote) {
  final recipes = <String, Recipe>{for (final item in remote.recipes) item.id: item};
  for (final item in local.recipes) {
    final current = recipes[item.id];
    if (current == null || item.updatedAt.isAfter(current.updatedAt)) {
      recipes[item.id] = item;
    }
  }
  final imports = <String, RecipeImport>{for (final item in remote.imports) item.id: item};
  for (final item in local.imports) {
    final current = imports[item.id];
    if (current == null || item.updatedAt.isAfter(current.updatedAt)) {
      imports[item.id] = item;
    }
  }
  final collections = <String, RecipeCollection>{
    for (final item in remote.collections) item.id: item,
    for (final item in local.collections) item.id: item,
  };
  final shopping = <String, ShoppingItem>{
    for (final item in remote.shoppingItems) item.id: item,
    for (final item in local.shoppingItems) item.id: item,
  };
  final records = <String, CookingRecord>{
    for (final item in remote.cookingRecords) item.id: item,
    for (final item in local.cookingRecords) item.id: item,
  };
  final feedback = <String, RecipeFeedback>{
    for (final item in remote.feedback) item.id: item,
    for (final item in local.feedback) item.id: item,
  };
  final allergy = local.allergySettings.allergens.isNotEmpty ||
          local.allergySettings.dislikedFoods.isNotEmpty
      ? local.allergySettings
      : remote.allergySettings;
  return RecipeSnapshot(
    recipes: recipes.values.toList(),
    imports: imports.values.toList(),
    collections: collections.values.toList(),
    shoppingItems: shopping.values.toList(),
    cookingRecords: records.values.toList(),
    feedback: feedback.values.toList(),
    allergySettings: allergy,
    sort: local.sort,
  );
}

String? _text(Map<String, dynamic> json, String first, [String? second]) {
  final value = json[first] ?? (second == null ? null : json[second]);
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text == 'null' ? null : text;
}

int? _integer(Map<String, dynamic> json, String first, [String? second]) {
  final value = json[first] ?? (second == null ? null : json[second]);
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '');
}

double? _number(Map<String, dynamic> json, String first, [String? second]) {
  final value = json[first] ?? (second == null ? null : json[second]);
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

List<String> _stringList(dynamic value) => value is List
    ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList()
    : const [];
