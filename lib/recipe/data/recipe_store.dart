import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/recipe_models.dart';

abstract class RecipeStore {
  Future<RecipeSnapshot> load();
  Future<void> save(RecipeSnapshot snapshot);
}

class SharedPreferencesRecipeStore implements RecipeStore {
  static const _snapshotKey = 'pinlogy_recipe_snapshot_v1';
  static const _backupKey = 'pinlogy_recipe_snapshot_backup_v1';

  @override
  Future<RecipeSnapshot> load() async {
    final preferences = await SharedPreferences.getInstance();
    for (final key in const [_snapshotKey, _backupKey]) {
      final raw = preferences.getString(key);
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return RecipeSnapshot.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        // The backup is attempted next. A malformed local snapshot must never
        // prevent the app from opening.
      }
    }
    return RecipeSnapshot();
  }

  @override
  Future<void> save(RecipeSnapshot snapshot) async {
    final preferences = await SharedPreferences.getInstance();
    final previous = preferences.getString(_snapshotKey);
    if (previous != null && previous.isNotEmpty) {
      await preferences.setString(_backupKey, previous);
    }
    await preferences.setString(_snapshotKey, jsonEncode(snapshot.toJson()));
  }
}

class MemoryRecipeStore implements RecipeStore {
  MemoryRecipeStore([RecipeSnapshot? initial])
    : _snapshot = initial ?? RecipeSnapshot();

  RecipeSnapshot _snapshot;

  @override
  Future<RecipeSnapshot> load() async =>
      RecipeSnapshot.fromJson(_snapshot.toJson());

  @override
  Future<void> save(RecipeSnapshot snapshot) async {
    _snapshot = RecipeSnapshot.fromJson(snapshot.toJson());
  }
}
