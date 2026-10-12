import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recipe_models.dart';

abstract class RecipeStore {
  Future<RecipeSnapshot> load({String? ownerId, bool migrateLegacy = false});
  Future<void> save(RecipeSnapshot snapshot, {String? ownerId});
  Future<void> clear({String? ownerId});
}

class SharedPreferencesRecipeStore implements RecipeStore {
  SharedPreferencesRecipeStore({
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;
  static const _snapshotKey = 'pinlogy_recipe_snapshot_v1';
  static const _backupKey = 'pinlogy_recipe_snapshot_backup_v1';
  static const _ownerKeyPrefix = 'pinlogy_recipe_snapshot_v2_';
  static const _ownerBackupPrefix = 'pinlogy_recipe_snapshot_backup_v2_';
  static const _legacyClaimedByKey = 'pinlogy_recipe_legacy_claimed_by_v1';

  String _suffix(String? ownerId) => ownerId?.trim().isNotEmpty == true
      ? ownerId!.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
      : 'signed_out';

  Future<Directory> _snapshotDirectory() async {
    final root = await _directoryProvider();
    final directory = Directory('${root.path}/recipe_snapshots');
    await directory.create(recursive: true);
    return directory;
  }

  Future<List<File>> _snapshotFiles(String suffix) async {
    final directory = await _snapshotDirectory();
    return [
      File('${directory.path}/$suffix.json'),
      File('${directory.path}/$suffix.backup.json'),
    ];
  }

  RecipeSnapshot? _decode(String raw) {
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return RecipeSnapshot.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // 呼び出し元が次のバックアップを試す。
    }
    return null;
  }

  @override
  Future<RecipeSnapshot> load({
    String? ownerId,
    bool migrateLegacy = false,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final suffix = _suffix(ownerId);
    try {
      for (final file in await _snapshotFiles(suffix)) {
        if (!await file.exists()) continue;
        final snapshot = _decode(await file.readAsString());
        if (snapshot != null) return snapshot;
      }
    } catch (_) {
      // 古いOS・テスト環境ではSharedPreferencesへフォールバックする。
    }
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
      final snapshot = _decode(raw);
      if (snapshot != null) {
        await save(snapshot, ownerId: ownerId);
        if ((key == _snapshotKey || key == _backupKey) && ownerId != null) {
          await preferences.setString(_legacyClaimedByKey, ownerId);
        }
        return snapshot;
      }
    }
    return RecipeSnapshot();
  }

  @override
  Future<void> save(RecipeSnapshot snapshot, {String? ownerId}) async {
    final suffix = _suffix(ownerId);
    final encoded = jsonEncode(snapshot.toJson());
    try {
      final files = await _snapshotFiles(suffix);
      final target = files[0];
      final backup = files[1];
      if (await target.exists() && await target.length() > 0) {
        await target.copy(backup.path);
      }
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsString(encoded, flush: true);
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
      return;
    } catch (_) {
      // 書き込み不能な環境だけ従来方式を使う。
    }
    final preferences = await SharedPreferences.getInstance();
    final snapshotKey = '$_ownerKeyPrefix$suffix';
    final backupKey = '$_ownerBackupPrefix$suffix';
    final previous = preferences.getString(snapshotKey);
    if (previous != null && previous.isNotEmpty) {
      await preferences.setString(backupKey, previous);
    }
    await preferences.setString(snapshotKey, encoded);
  }

  @override
  Future<void> clear({String? ownerId}) async {
    final preferences = await SharedPreferences.getInstance();
    final suffix = _suffix(ownerId);
    try {
      for (final file in await _snapshotFiles(suffix)) {
        if (await file.exists()) await file.delete();
      }
    } catch (_) {
      // SharedPreferences側の削除は続行する。
    }
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
