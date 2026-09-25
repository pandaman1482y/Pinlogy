import '../../core/ids.dart';

enum RecipeStatus {
  pending('解析中'),
  needsReview('要確認'),
  ready('完了'),
  failed('失敗');

  const RecipeStatus(this.label);
  final String label;

  static RecipeStatus fromName(String? value) => values.firstWhere(
    (item) => item.name == value,
    orElse: () => RecipeStatus.needsReview,
  );
}

enum RecipeImportStatus {
  queued('受付済み'),
  fetching('取得中'),
  analyzing('解析中'),
  awaitingSelection('保存する料理を選択'),
  completed('完了'),
  retryWaiting('再試行待ち'),
  failed('失敗'),
  cancelled('キャンセル');

  const RecipeImportStatus(this.label);
  final String label;

  static RecipeImportStatus fromName(String? value) => values.firstWhere(
    (item) => item.name == value,
    orElse: () => RecipeImportStatus.queued,
  );
}

enum RecipeSort {
  newest('保存が新しい順'),
  recentlyMade('最近作った順'),
  favorites('お気に入り優先'),
  name('名前順'),
  shortest('調理時間が短い順');

  const RecipeSort(this.label);
  final String label;

  static RecipeSort fromName(String? value) => values.firstWhere(
    (item) => item.name == value,
    orElse: () => RecipeSort.newest,
  );
}

enum EvidenceKind {
  image,
  video,
  caption,
  authorComment,
  audio,
  aiInference,
  user;

  static EvidenceKind fromName(String? value) => values.firstWhere(
    (item) => item.name == value,
    orElse: () => EvidenceKind.aiInference,
  );
}

class RecipeEvidence {
  RecipeEvidence({
    String? id,
    required this.kind,
    required this.label,
    this.imagePath,
    this.timestampSeconds,
    this.excerpt,
    this.confidencePercent,
  }) : id = id ?? newId();

  final String id;
  final EvidenceKind kind;
  final String label;
  final String? imagePath;
  final int? timestampSeconds;
  final String? excerpt;
  final int? confidencePercent;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'label': label,
    'imagePath': imagePath,
    'timestampSeconds': timestampSeconds,
    'excerpt': excerpt,
    'confidencePercent': confidencePercent,
  };

  factory RecipeEvidence.fromJson(Map<String, dynamic> json) => RecipeEvidence(
    id: json['id']?.toString(),
    kind: EvidenceKind.fromName(json['kind']?.toString()),
    label: json['label']?.toString() ?? '根拠',
    imagePath: json['imagePath']?.toString(),
    timestampSeconds: (json['timestampSeconds'] as num?)?.toInt(),
    excerpt: json['excerpt']?.toString(),
    confidencePercent: (json['confidencePercent'] as num?)?.toInt(),
  );
}

class RecipeIngredient {
  RecipeIngredient({
    String? id,
    required this.name,
    this.amount,
    this.unit,
    this.originalText,
    this.note,
    this.scalable = true,
    this.evidenceId,
    this.confidencePercent,
    this.userEdited = false,
  }) : id = id ?? newId();

  final String id;
  final String name;
  final double? amount;
  final String? unit;
  final String? originalText;
  final String? note;
  final bool scalable;
  final String? evidenceId;
  final int? confidencePercent;
  final bool userEdited;

  String quantityFor(double multiplier) {
    if (!scalable || amount == null) {
      return originalText?.trim().isNotEmpty == true
          ? originalText!.trim()
          : [amount, unit].whereType<Object>().join(' ');
    }
    final scaled = amount! * multiplier;
    final value = _practicalAmount(scaled, unit);
    final unitText = unit?.trim() ?? '';
    if (unitText.isEmpty) return value;
    const prefixUnits = {'大さじ', '小さじ', 'カップ'};
    return prefixUnits.contains(unitText)
        ? '$unitText$value'
        : '$value$unitText';
  }

  RecipeIngredient copyWith({
    String? name,
    double? amount,
    String? unit,
    String? originalText,
    String? note,
    bool? scalable,
    String? evidenceId,
    int? confidencePercent,
    bool? userEdited,
  }) => RecipeIngredient(
    id: id,
    name: name ?? this.name,
    amount: amount ?? this.amount,
    unit: unit ?? this.unit,
    originalText: originalText ?? this.originalText,
    note: note ?? this.note,
    scalable: scalable ?? this.scalable,
    evidenceId: evidenceId ?? this.evidenceId,
    confidencePercent: confidencePercent ?? this.confidencePercent,
    userEdited: userEdited ?? this.userEdited,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'amount': amount,
    'unit': unit,
    'originalText': originalText,
    'note': note,
    'scalable': scalable,
    'evidenceId': evidenceId,
    'confidencePercent': confidencePercent,
    'userEdited': userEdited,
  };

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) =>
      RecipeIngredient(
        id: json['id']?.toString(),
        name: json['name']?.toString() ?? '材料',
        amount: (json['amount'] as num?)?.toDouble(),
        unit: json['unit']?.toString(),
        originalText: json['originalText']?.toString(),
        note: json['note']?.toString(),
        scalable: json['scalable'] as bool? ?? true,
        evidenceId: json['evidenceId']?.toString(),
        confidencePercent: (json['confidencePercent'] as num?)?.toInt(),
        userEdited: json['userEdited'] as bool? ?? false,
      );
}

class RecipeStep {
  RecipeStep({
    String? id,
    required this.order,
    required this.instruction,
    this.durationSeconds,
    this.imageIndex,
    List<int>? ingredientIndexes,
    this.evidenceId,
    this.confidencePercent,
    this.userEdited = false,
  }) : id = id ?? newId(),
       ingredientIndexes = ingredientIndexes ?? const [];

  final String id;
  final int order;
  final String instruction;
  final int? durationSeconds;
  final int? imageIndex;
  final List<int> ingredientIndexes;
  final String? evidenceId;
  final int? confidencePercent;
  final bool userEdited;

  Map<String, dynamic> toJson() => {
    'id': id,
    'order': order,
    'instruction': instruction,
    'durationSeconds': durationSeconds,
    'imageIndex': imageIndex,
    'ingredientIndexes': ingredientIndexes,
    'evidenceId': evidenceId,
    'confidencePercent': confidencePercent,
    'userEdited': userEdited,
  };

  factory RecipeStep.fromJson(Map<String, dynamic> json) => RecipeStep(
    id: json['id']?.toString(),
    order: (json['order'] as num?)?.toInt() ?? 1,
    instruction: json['instruction']?.toString() ?? '',
    durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
    imageIndex: (json['imageIndex'] as num?)?.toInt(),
    ingredientIndexes: (json['ingredientIndexes'] as List? ?? const [])
        .whereType<num>()
        .map((value) => value.toInt())
        .toList(growable: false),
    evidenceId: json['evidenceId']?.toString(),
    confidencePercent: (json['confidencePercent'] as num?)?.toInt(),
    userEdited: json['userEdited'] as bool? ?? false,
  );
}

class RecipePart {
  RecipePart({
    String? id,
    required this.name,
    List<RecipeIngredient>? ingredients,
    List<RecipeStep>? steps,
  }) : id = id ?? newId(),
       ingredients = ingredients ?? [],
       steps = steps ?? [];

  final String id;
  final String name;
  final List<RecipeIngredient> ingredients;
  final List<RecipeStep> steps;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ingredients': ingredients.map((item) => item.toJson()).toList(),
    'steps': steps.map((item) => item.toJson()).toList(),
  };

  factory RecipePart.fromJson(Map<String, dynamic> json) => RecipePart(
    id: json['id']?.toString(),
    name: json['name']?.toString() ?? '本体',
    ingredients: _mapList(json['ingredients'], RecipeIngredient.fromJson),
    steps: _mapList(json['steps'], RecipeStep.fromJson),
  );
}

class RecipeNutrition {
  const RecipeNutrition({
    this.calories,
    this.proteinGrams,
    this.fatGrams,
    this.carbohydrateGrams,
    this.approximate = true,
  });

  final int? calories;
  final double? proteinGrams;
  final double? fatGrams;
  final double? carbohydrateGrams;
  final bool approximate;

  Map<String, dynamic> toJson() => {
    'calories': calories,
    'proteinGrams': proteinGrams,
    'fatGrams': fatGrams,
    'carbohydrateGrams': carbohydrateGrams,
    'approximate': approximate,
  };

  factory RecipeNutrition.fromJson(Map<String, dynamic> json) =>
      RecipeNutrition(
        calories: (json['calories'] as num?)?.round(),
        proteinGrams: (json['proteinGrams'] as num?)?.toDouble(),
        fatGrams: (json['fatGrams'] as num?)?.toDouble(),
        carbohydrateGrams: (json['carbohydrateGrams'] as num?)?.toDouble(),
        approximate: json['approximate'] as bool? ?? true,
      );
}

class Recipe {
  Recipe({
    String? id,
    required this.sourcePostId,
    required this.title,
    this.description,
    this.servings = 2,
    this.servingUnit = '人分',
    this.totalMinutes,
    this.difficulty,
    this.category,
    this.cuisine,
    this.mainIngredient,
    this.method,
    List<RecipePart>? parts,
    List<RecipeEvidence>? evidence,
    this.coverImagePath,
    this.sourceUrl,
    this.sourceService,
    this.sourceAuthor,
    this.status = RecipeStatus.needsReview,
    this.isFavorite = false,
    this.isSaved = true,
    List<String>? allergens,
    List<String>? warnings,
    List<String>? needsReviewFields,
    Set<String>? userEditedFields,
    this.userNote,
    this.nutrition,
    this.lastMadeAt,
    this.madeCount = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? newId(),
       parts = parts ?? [],
       evidence = evidence ?? [],
       allergens = allergens ?? [],
       warnings = warnings ?? [],
       needsReviewFields = needsReviewFields ?? [],
       userEditedFields = userEditedFields ?? <String>{},
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String sourcePostId;
  final String title;
  final String? description;
  final double servings;
  final String servingUnit;
  final int? totalMinutes;
  final String? difficulty;
  final String? category;
  final String? cuisine;
  final String? mainIngredient;
  final String? method;
  final List<RecipePart> parts;
  final List<RecipeEvidence> evidence;
  final String? coverImagePath;
  final String? sourceUrl;
  final String? sourceService;
  final String? sourceAuthor;
  final RecipeStatus status;
  final bool isFavorite;
  final bool isSaved;
  final List<String> allergens;
  final List<String> warnings;
  final List<String> needsReviewFields;
  final Set<String> userEditedFields;
  final String? userNote;
  final RecipeNutrition? nutrition;
  final DateTime? lastMadeAt;
  final int madeCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  Iterable<RecipeIngredient> get allIngredients =>
      parts.expand((part) => part.ingredients);
  Iterable<RecipeStep> get allSteps => parts.expand((part) => part.steps);

  Recipe copyWith({
    String? title,
    String? description,
    double? servings,
    String? servingUnit,
    int? totalMinutes,
    String? difficulty,
    String? category,
    String? cuisine,
    String? mainIngredient,
    String? method,
    List<RecipePart>? parts,
    List<RecipeEvidence>? evidence,
    String? coverImagePath,
    String? sourceUrl,
    String? sourceService,
    String? sourceAuthor,
    RecipeStatus? status,
    bool? isFavorite,
    bool? isSaved,
    List<String>? allergens,
    List<String>? warnings,
    List<String>? needsReviewFields,
    Set<String>? userEditedFields,
    String? userNote,
    RecipeNutrition? nutrition,
    DateTime? lastMadeAt,
    int? madeCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Recipe(
    id: id,
    sourcePostId: sourcePostId,
    title: title ?? this.title,
    description: description ?? this.description,
    servings: servings ?? this.servings,
    servingUnit: servingUnit ?? this.servingUnit,
    totalMinutes: totalMinutes ?? this.totalMinutes,
    difficulty: difficulty ?? this.difficulty,
    category: category ?? this.category,
    cuisine: cuisine ?? this.cuisine,
    mainIngredient: mainIngredient ?? this.mainIngredient,
    method: method ?? this.method,
    parts: parts ?? this.parts,
    evidence: evidence ?? this.evidence,
    coverImagePath: coverImagePath ?? this.coverImagePath,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    sourceService: sourceService ?? this.sourceService,
    sourceAuthor: sourceAuthor ?? this.sourceAuthor,
    status: status ?? this.status,
    isFavorite: isFavorite ?? this.isFavorite,
    isSaved: isSaved ?? this.isSaved,
    allergens: allergens ?? this.allergens,
    warnings: warnings ?? this.warnings,
    needsReviewFields: needsReviewFields ?? this.needsReviewFields,
    userEditedFields: userEditedFields ?? this.userEditedFields,
    userNote: userNote ?? this.userNote,
    nutrition: nutrition ?? this.nutrition,
    lastMadeAt: lastMadeAt ?? this.lastMadeAt,
    madeCount: madeCount ?? this.madeCount,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourcePostId': sourcePostId,
    'title': title,
    'description': description,
    'servings': servings,
    'servingUnit': servingUnit,
    'totalMinutes': totalMinutes,
    'difficulty': difficulty,
    'category': category,
    'cuisine': cuisine,
    'mainIngredient': mainIngredient,
    'method': method,
    'parts': parts.map((item) => item.toJson()).toList(),
    'evidence': evidence.map((item) => item.toJson()).toList(),
    'coverImagePath': coverImagePath,
    'sourceUrl': sourceUrl,
    'sourceService': sourceService,
    'sourceAuthor': sourceAuthor,
    'status': status.name,
    'isFavorite': isFavorite,
    'isSaved': isSaved,
    'allergens': allergens,
    'warnings': warnings,
    'needsReviewFields': needsReviewFields,
    'userEditedFields': userEditedFields.toList(),
    'userNote': userNote,
    'nutrition': nutrition?.toJson(),
    'lastMadeAt': lastMadeAt?.toIso8601String(),
    'madeCount': madeCount,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Recipe.fromJson(Map<String, dynamic> json) => Recipe(
    id: json['id']?.toString(),
    sourcePostId: json['sourcePostId']?.toString() ?? '',
    title: json['title']?.toString() ?? '名称未設定のレシピ',
    description: json['description']?.toString(),
    servings: (json['servings'] as num?)?.toDouble() ?? 2,
    servingUnit: json['servingUnit']?.toString().trim().isNotEmpty == true
        ? json['servingUnit'].toString().trim()
        : '人分',
    totalMinutes: (json['totalMinutes'] as num?)?.toInt(),
    difficulty: json['difficulty']?.toString(),
    category: json['category']?.toString(),
    cuisine: json['cuisine']?.toString(),
    mainIngredient: json['mainIngredient']?.toString(),
    method: json['method']?.toString(),
    parts: _mapList(json['parts'], RecipePart.fromJson),
    evidence: _mapList(json['evidence'], RecipeEvidence.fromJson),
    coverImagePath: json['coverImagePath']?.toString(),
    sourceUrl: json['sourceUrl']?.toString(),
    sourceService: json['sourceService']?.toString(),
    sourceAuthor: json['sourceAuthor']?.toString(),
    status: RecipeStatus.fromName(json['status']?.toString()),
    isFavorite: json['isFavorite'] as bool? ?? false,
    isSaved: json['isSaved'] as bool? ?? true,
    allergens: _strings(json['allergens']),
    warnings: _strings(json['warnings']),
    needsReviewFields: _strings(json['needsReviewFields']),
    userEditedFields: _strings(json['userEditedFields']).toSet(),
    userNote: json['userNote']?.toString(),
    nutrition: json['nutrition'] is Map
        ? RecipeNutrition.fromJson(
            Map<String, dynamic>.from(json['nutrition'] as Map),
          )
        : null,
    lastMadeAt: _date(json['lastMadeAt']),
    madeCount: (json['madeCount'] as num?)?.toInt() ?? 0,
    createdAt: _date(json['createdAt']) ?? DateTime.now(),
    updatedAt: _date(json['updatedAt']) ?? DateTime.now(),
  );
}

class RecipeImport {
  RecipeImport({
    String? id,
    required this.sourcePostId,
    this.sourceUrl,
    this.sourceService,
    this.coverImagePath,
    this.status = RecipeImportStatus.queued,
    this.message,
    List<String>? recipeIds,
    this.requiresSelection = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? newId(),
       recipeIds = recipeIds ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String sourcePostId;
  final String? sourceUrl;
  final String? sourceService;
  final String? coverImagePath;
  final RecipeImportStatus status;
  final String? message;
  final List<String> recipeIds;
  final bool requiresSelection;
  final DateTime createdAt;
  final DateTime updatedAt;

  RecipeImport copyWith({
    String? sourceUrl,
    String? sourceService,
    String? coverImagePath,
    RecipeImportStatus? status,
    String? message,
    List<String>? recipeIds,
    bool? requiresSelection,
  }) => RecipeImport(
    id: id,
    sourcePostId: sourcePostId,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    sourceService: sourceService ?? this.sourceService,
    coverImagePath: coverImagePath ?? this.coverImagePath,
    status: status ?? this.status,
    message: message ?? this.message,
    recipeIds: recipeIds ?? this.recipeIds,
    requiresSelection: requiresSelection ?? this.requiresSelection,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourcePostId': sourcePostId,
    'sourceUrl': sourceUrl,
    'sourceService': sourceService,
    'coverImagePath': coverImagePath,
    'status': status.name,
    'message': message,
    'recipeIds': recipeIds,
    'requiresSelection': requiresSelection,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory RecipeImport.fromJson(Map<String, dynamic> json) => RecipeImport(
    id: json['id']?.toString(),
    sourcePostId: json['sourcePostId']?.toString() ?? '',
    sourceUrl: json['sourceUrl']?.toString(),
    sourceService: json['sourceService']?.toString(),
    coverImagePath: json['coverImagePath']?.toString(),
    status: RecipeImportStatus.fromName(json['status']?.toString()),
    message: json['message']?.toString(),
    recipeIds: _strings(json['recipeIds']),
    requiresSelection: json['requiresSelection'] as bool? ?? false,
    createdAt: _date(json['createdAt']) ?? DateTime.now(),
    updatedAt: _date(json['updatedAt']) ?? DateTime.now(),
  );
}

class RecipeCollection {
  RecipeCollection({
    String? id,
    required this.name,
    List<String>? recipeIds,
    this.isFavoriteCollection = false,
  }) : id = id ?? newId(),
       recipeIds = recipeIds ?? [];

  final String id;
  final String name;
  final List<String> recipeIds;
  final bool isFavoriteCollection;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'recipeIds': recipeIds,
    'isFavoriteCollection': isFavoriteCollection,
  };

  factory RecipeCollection.fromJson(Map<String, dynamic> json) =>
      RecipeCollection(
        id: json['id']?.toString(),
        name: json['name']?.toString() ?? 'コレクション',
        recipeIds: _strings(json['recipeIds']),
        isFavoriteCollection: json['isFavoriteCollection'] as bool? ?? false,
      );
}

class ShoppingItem {
  ShoppingItem({
    String? id,
    required this.name,
    this.quantity = '',
    this.checked = false,
    List<String>? recipeIds,
  }) : id = id ?? newId(),
       recipeIds = recipeIds ?? [];

  final String id;
  final String name;
  final String quantity;
  final bool checked;
  final List<String> recipeIds;

  ShoppingItem copyWith({String? quantity, bool? checked}) => ShoppingItem(
    id: id,
    name: name,
    quantity: quantity ?? this.quantity,
    checked: checked ?? this.checked,
    recipeIds: recipeIds,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'quantity': quantity,
    'checked': checked,
    'recipeIds': recipeIds,
  };

  factory ShoppingItem.fromJson(Map<String, dynamic> json) => ShoppingItem(
    id: json['id']?.toString(),
    name: json['name']?.toString() ?? '',
    quantity: json['quantity']?.toString() ?? '',
    checked: json['checked'] as bool? ?? false,
    recipeIds: _strings(json['recipeIds']),
  );
}

class CookingRecord {
  CookingRecord({
    String? id,
    required this.recipeId,
    DateTime? madeAt,
    this.rating,
    this.note,
    this.photoPath,
  }) : id = id ?? newId(),
       madeAt = madeAt ?? DateTime.now();

  final String id;
  final String recipeId;
  final DateTime madeAt;
  final int? rating;
  final String? note;
  final String? photoPath;

  Map<String, dynamic> toJson() => {
    'id': id,
    'recipeId': recipeId,
    'madeAt': madeAt.toIso8601String(),
    'rating': rating,
    'note': note,
    'photoPath': photoPath,
  };

  factory CookingRecord.fromJson(Map<String, dynamic> json) => CookingRecord(
    id: json['id']?.toString(),
    recipeId: json['recipeId']?.toString() ?? '',
    madeAt: _date(json['madeAt']) ?? DateTime.now(),
    rating: (json['rating'] as num?)?.toInt(),
    note: json['note']?.toString(),
    photoPath: json['photoPath']?.toString(),
  );
}

class RecipeFeedback {
  RecipeFeedback({
    String? id,
    required this.recipeId,
    required this.type,
    this.comment,
    DateTime? createdAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String recipeId;
  final String type;
  final String? comment;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'recipeId': recipeId,
    'type': type,
    'comment': comment,
    'createdAt': createdAt.toIso8601String(),
  };

  factory RecipeFeedback.fromJson(Map<String, dynamic> json) => RecipeFeedback(
    id: json['id']?.toString(),
    recipeId: json['recipeId']?.toString() ?? '',
    type: json['type']?.toString() ?? 'その他',
    comment: json['comment']?.toString(),
    createdAt: _date(json['createdAt']) ?? DateTime.now(),
  );
}

class AllergySettings {
  const AllergySettings({
    this.allergens = const [],
    this.dislikedFoods = const [],
    this.improvementSharingEnabled = true,
  });

  final List<String> allergens;
  final List<String> dislikedFoods;
  final bool improvementSharingEnabled;

  Map<String, dynamic> toJson() => {
    'allergens': allergens,
    'dislikedFoods': dislikedFoods,
    'improvementSharingEnabled': improvementSharingEnabled,
  };

  factory AllergySettings.fromJson(Map<String, dynamic> json) =>
      AllergySettings(
        allergens: _strings(json['allergens']),
        dislikedFoods: _strings(json['dislikedFoods']),
        improvementSharingEnabled:
            json['improvementSharingEnabled'] as bool? ?? true,
      );
}

class RecipeSnapshot {
  RecipeSnapshot({
    List<Recipe>? recipes,
    List<RecipeImport>? imports,
    List<RecipeCollection>? collections,
    List<ShoppingItem>? shoppingItems,
    List<CookingRecord>? cookingRecords,
    List<RecipeFeedback>? feedback,
    this.allergySettings = const AllergySettings(),
    this.sort = RecipeSort.newest,
  }) : recipes = recipes ?? [],
       imports = imports ?? [],
       collections = collections ?? [],
       shoppingItems = shoppingItems ?? [],
       cookingRecords = cookingRecords ?? [],
       feedback = feedback ?? [];

  final List<Recipe> recipes;
  final List<RecipeImport> imports;
  final List<RecipeCollection> collections;
  final List<ShoppingItem> shoppingItems;
  final List<CookingRecord> cookingRecords;
  final List<RecipeFeedback> feedback;
  final AllergySettings allergySettings;
  final RecipeSort sort;

  Map<String, dynamic> toJson() => {
    'recipes': recipes.map((item) => item.toJson()).toList(),
    'imports': imports.map((item) => item.toJson()).toList(),
    'collections': collections.map((item) => item.toJson()).toList(),
    'shoppingItems': shoppingItems.map((item) => item.toJson()).toList(),
    'cookingRecords': cookingRecords.map((item) => item.toJson()).toList(),
    'feedback': feedback.map((item) => item.toJson()).toList(),
    'allergySettings': allergySettings.toJson(),
    'sort': sort.name,
  };

  factory RecipeSnapshot.fromJson(Map<String, dynamic> json) => RecipeSnapshot(
    recipes: _mapList(json['recipes'], Recipe.fromJson),
    imports: _mapList(json['imports'], RecipeImport.fromJson),
    collections: _mapList(json['collections'], RecipeCollection.fromJson),
    shoppingItems: _mapList(json['shoppingItems'], ShoppingItem.fromJson),
    cookingRecords: _mapList(json['cookingRecords'], CookingRecord.fromJson),
    feedback: _mapList(json['feedback'], RecipeFeedback.fromJson),
    allergySettings: json['allergySettings'] is Map
        ? AllergySettings.fromJson(
            Map<String, dynamic>.from(json['allergySettings'] as Map),
          )
        : const AllergySettings(),
    sort: RecipeSort.fromName(json['sort']?.toString()),
  );
}

List<T> _mapList<T>(dynamic value, T Function(Map<String, dynamic>) convert) {
  if (value is! List) return <T>[];
  return value
      .whereType<Map>()
      .map((item) => convert(Map<String, dynamic>.from(item)))
      .toList();
}

List<String> _strings(dynamic value) => value is List
    ? value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList()
    : <String>[];

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString());

String _practicalAmount(double value, String? unit) {
  if (value <= 0) return '0';
  final normalizedUnit = unit?.trim().toLowerCase();
  if (normalizedUnit == 'g' || normalizedUnit == 'ml') {
    final rounded = value >= 100 ? (value / 5).round() * 5 : value.round();
    return '$rounded';
  }
  final whole = value.floor();
  final fraction = value - whole;
  final candidates = <double, String>{
    1 / 8: '1/8',
    1 / 6: '1/6',
    1 / 4: '1/4',
    1 / 3: '1/3',
    1 / 2: '1/2',
    2 / 3: '2/3',
    3 / 4: '3/4',
    5 / 6: '5/6',
    7 / 8: '7/8',
  };
  var closest = candidates.keys.first;
  for (final candidate in candidates.keys) {
    if ((fraction - candidate).abs() < (fraction - closest).abs()) {
      closest = candidate;
    }
  }
  if (fraction < 0.04) return '$whole';
  if (fraction > 0.96) return '${whole + 1}';
  if ((fraction - closest).abs() <= 0.035) {
    final fractionText = candidates[closest]!;
    return whole == 0 ? fractionText : '$wholeと$fractionText';
  }

  // 料理で一般的な分数から離れた値は、無理に丸めず小数で表示する。
  final decimal = value.toStringAsFixed(2);
  return decimal.replaceFirst(RegExp(r'\.?0+$'), '');
}
