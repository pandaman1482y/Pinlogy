import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/recipe_models.dart';

abstract class RecipeStore {
  Future<RecipeSnapshot> load({String? ownerId, bool migrateLegacy = false});
  Future<void> save(RecipeSnapshot snapshot, {String? ownerId});
  Future<void> clear({String? ownerId});
}

class SharedPreferencesRecipeStore implements RecipeStore {
  static const _snapshotKey = 'pinlogy_recipe_snapshot_v1';
  static const _backupKey = 'pinlogy_recipe_snapshot_backup_v1';
  static const _ownerKeyPrefix = 'pinlogy_recipe_snapshot_v2_';
  static const _ownerBackupPrefix = 'pinlogy_recipe_snapshot_backup_v2_';
  static const _legacyClaimedByKey = 'pinlogy_recipe_legacy_claimed_by_v1';

  String _suffix(String? ownerId) => ownerId?.trim().isNotEmpty == true
      ? ownerId!.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
      : 'signed_out';

  @override
  Future<RecipeSnapshot> load({
    String? ownerId,
    bool migrateLegacy = false,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final suffix = _suffix(ownerId);
    final keys = <String>[
      '$_ownerKeyPrefix$suffix',
      '$_ownerBackupPrefix$suffix',
    ];
    if (migrateLegacy && ownerId != null) {
      final claimedBy = preferences.getString(_legacyClaimedByKey);
      if (claimedBy == null || claimedBy == ownerId) {
        keys.addAll(const [_snapshotKey, _backupKey]);
      }
    }
    for (final key in keys) {
      final raw = preferences.getString(key);
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final snapshot = RecipeSnapshot.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          if (key == _snapshotKey || key == _backupKey) {
            await save(snapshot, ownerId: ownerId);
            await preferences.setString(_legacyClaimedByKey, ownerId!);
          }
          return snapshot;
        }
      } catch (_) {
        // The backup is attempted next. A malformed local snapshot must never
        // prevent the app from opening.
      }
    }
    return RecipeSnapshot();
  }

  @override
  Future<void> save(RecipeSnapshot snapshot, {String? ownerId}) async {
    final preferences = await SharedPreferences.getInstance();
    final suffix = _suffix(ownerId);
    final snapshotKey = '$_ownerKeyPrefix$suffix';
    final backupKey = '$_ownerBackupPrefix$suffix';
    final previous = preferences.getString(snapshotKey);
    if (previous != null && previous.isNotEmpty) {
      await preferences.setString(backupKey, previous);
    }
    await preferences.setString(snapshotKey, jsonEncode(snapshot.toJson()));
  }

  @override
  Future<void> clear({String? ownerId}) async {
    final preferences = await SharedPreferences.getInstance();
    final suffix = _suffix(ownerId);
    await preferences.remove('$_ownerKeyPrefix$suffix');
    await preferences.remove('$_ownerBackupPrefix$suffix');
  }
}

class MemoryRecipeStore implements RecipeStore {
  MemoryRecipeStore([RecipeSnapshot? initial])
    : _snapshot = initial ?? RecipeSnapshot();

  RecipeSnapshot _snapshot;

  @override
  Future<RecipeSnapshot> load({
    String? ownerId,
    bool migrateLegacy = false,
  }) async => RecipeSnapshot.fromJson(_snapshot.toJson());

  @override
  Future<void> save(RecipeSnapshot snapshot, {String? ownerId}) async {
    _snapshot = RecipeSnapshot.fromJson(snapshot.toJson());
  }

  @override
  Future<void> clear({String? ownerId}) async {
    _snapshot = RecipeSnapshot();
  }
}
