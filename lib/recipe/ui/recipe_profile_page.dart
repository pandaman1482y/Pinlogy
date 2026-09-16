import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../models/recipe_models.dart';
import '../recipe_scope.dart';
import 'recipe_widgets.dart';
import '../../services/notification_service.dart';

class RecipeProfilePage extends StatelessWidget {
  const RecipeProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = RecipeScope.of(context);
    final user = controller.legacy.cloud.user;
    return Scaffold(
      appBar: AppBar(title: const Text('マイページ')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          SoftPanel(
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: mint,
                  child: Icon(Icons.person_outline_rounded, color: mossDeep, size: 30),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.email ?? '端末に保存中', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 3),
                      Text(
                        '${controller.savedRecipes.length}レシピ · ${controller.snapshot.cookingRecords.length}回作った',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('レシピ管理', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          _MenuTile(
            icon: Icons.shopping_cart_outlined,
            title: '買い物リスト',
            subtitle: '${controller.snapshot.shoppingItems.where((item) => !item.checked).length}件',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ShoppingListPage()),
            ),
          ),
          _MenuTile(
            icon: Icons.folder_outlined,
            title: 'コレクション',
            subtitle: '${controller.snapshot.collections.length}個',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RecipeCollectionsPage()),
            ),
          ),
          _MenuTile(
            icon: Icons.cloud_sync_outlined,
            title: '取り込み状況',
            subtitle: '${controller.activeImports.length}件の確認・処理中',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ImportStatusPage()),
            ),
          ),
          const SizedBox(height: 22),
          Text('設定', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            secondary: const Icon(Icons.notifications_outlined, color: mossDeep),
            title: const Text('解析完了の通知'),
            subtitle: Text(
              controller.notificationsReady
                  ? 'アプリを閉じていても完了を知らせます'
                  : 'Firebaseまたは端末の通知設定を確認してください',
            ),
            value: controller.notificationsEnabled,
            onChanged: (value) => _setNotifications(context, value),
          ),
          _MenuTile(
            icon: Icons.notification_important_outlined,
            title: 'テスト通知を送る',
            subtitle: controller.notificationsReady
                ? 'APNs・FCM・サーバー設定をまとめて確認'
                : 'Firebaseが未接続です',
            onTap: () => _testNotification(context),
          ),
          _MenuTile(
            icon: Icons.info_outline_rounded,
            title: '通知の接続状態',
            subtitle: '端末権限と通知トークンを確認',
            onTap: () => _showNotificationStatus(context),
          ),
          _MenuTile(
            icon: Icons.health_and_safety_outlined,
            title: 'アレルギー・苦手な食材',
            subtitle: 'AI提案と注意表示に使用',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AllergySettingsPage()),
            ),
          ),
          _MenuTile(
            icon: Icons.swap_vert_rounded,
            title: '一覧の並び順',
            subtitle: controller.snapshot.sort.label,
            onTap: () => _selectSort(context),
          ),
          const SizedBox(height: 22),
          Text('アカウント', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          if (user == null) ...[
            _MenuTile(
              icon: Icons.apple,
              title: 'Appleでログイン',
              subtitle: 'iPhoneで同じレシピを引き継ぐ',
              onTap: () => _signIn(context, apple: true),
            ),
            _MenuTile(
              icon: Icons.g_mobiledata_rounded,
              title: 'Googleでログイン',
              subtitle: 'iPhone・Androidで同じアカウントを使う',
              onTap: () => _signIn(context, apple: false),
            ),
          ] else
            ...[
              _MenuTile(
                icon: Icons.cloud_sync_rounded,
                title: '今すぐ同期',
                subtitle: 'iPhone・Android間でレシピを統合',
                onTap: () => _syncCloud(context),
              ),
              _MenuTile(
                icon: Icons.logout_rounded,
                title: 'ログアウト',
                subtitle: '端末内のレシピは残ります',
                onTap: () async {
                  await controller.legacy.cloud.signOut();
                  if (context.mounted) controller.notifyListeners();
                },
              ),
            ],
          const SizedBox(height: 22),
          const SoftPanel(
            child: Text(
              'AI解析は投稿内の文字・音声・画像をもとに整理します。内容やアレルゲンを完全には判定できないため、調理前に必ず元投稿と商品表示を確認してください。',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setNotifications(BuildContext context, bool value) async {
    final controller = RecipeScope.read(context);
    final accepted = await controller.setNotificationsEnabled(value);
    if (!context.mounted) return;
    if (!accepted && value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('通知を有効にできませんでした。iPhoneの設定とFirebase構成を確認してください。')),
      );
    }
  }

  Future<void> _testNotification(BuildContext context) async {
    final sent = await PinlogyNotificationService.instance.sendTestNotification();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? 'テスト通知を送信しました。数秒待って確認してください。'
              : '送信できませんでした。通知権限・Firebase・Edge Functionの設定を確認してください。',
        ),
      ),
    );
  }

  Future<void> _showNotificationStatus(BuildContext context) async {
    final status = await PinlogyNotificationService.instance.diagnostics();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('通知の接続状態'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                status.firebaseReady
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                color: status.firebaseReady ? moss : errorColor,
              ),
              title: const Text('Firebase'),
              trailing: Text(status.firebaseReady ? '接続済み' : '未接続'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('端末の通知権限'),
              trailing: Text(status.permission),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                status.tokenReady
                    ? Icons.vpn_key_rounded
                    : Icons.key_off_rounded,
              ),
              title: const Text('通知トークン'),
              trailing: Text(status.tokenReady ? '取得済み' : '未取得'),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Future<void> _selectSort(BuildContext context) async {
    final controller = RecipeScope.read(context);
    final selected = await showModalBottomSheet<RecipeSort>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final sort in RecipeSort.values)
              RadioListTile<RecipeSort>(
                value: sort,
                groupValue: controller.snapshot.sort,
                title: Text(sort.label),
                onChanged: (value) => Navigator.pop(sheetContext, value),
              ),
          ],
        ),
      ),
    );
    if (selected != null) await controller.setSort(selected);
  }

  Future<void> _signIn(BuildContext context, {required bool apple}) async {
    final cloud = RecipeScope.read(context).legacy.cloud;
    try {
      apple ? await cloud.signInWithApple() : await cloud.signInWithGoogle();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ログインを開始できませんでした: $error')));
    }
  }

  Future<void> _syncCloud(BuildContext context) async {
    final controller = RecipeScope.read(context);
    try {
      await controller.syncCloud();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('レシピを同期しました')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('同期できませんでした: $error')),
      );
    }
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    leading: Icon(icon, color: mossDeep),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

class ShoppingListPage extends StatefulWidget {
  const ShoppingListPage({super.key});

  @override
  State<ShoppingListPage> createState() => _ShoppingListPageState();
}

class _ShoppingListPageState extends State<ShoppingListPage> {
  @override
  Widget build(BuildContext context) {
    final controller = RecipeScope.of(context);
    final items = controller.snapshot.shoppingItems;
    return Scaffold(
      appBar: AppBar(
        title: const Text('買い物リスト'),
        actions: [
          if (items.any((item) => item.checked))
            TextButton(onPressed: controller.clearPurchasedItems, child: const Text('購入済みを削除')),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '買うものを追加',
        onPressed: () => _add(context),
        child: const Icon(Icons.add_rounded),
      ),
      body: items.isEmpty
          ? const Center(child: Text('買うものはまだありません'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
              itemCount: items.length,
              itemBuilder: (_, index) {
                final item = items[index];
                return CheckboxListTile(
                  value: item.checked,
                  onChanged: (_) => controller.toggleShoppingItem(item),
                  title: Text(
                    item.name,
                    style: TextStyle(decoration: item.checked ? TextDecoration.lineThrough : null),
                  ),
                  subtitle: item.quantity.isEmpty ? null : Text(item.quantity),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final name = TextEditingController();
    final quantity = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('買うものを追加'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: '品名')),
            const SizedBox(height: 10),
            TextField(controller: quantity, decoration: const InputDecoration(labelText: '数量（任意）')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('追加')),
        ],
      ),
    );
    if (accepted == true && context.mounted) {
      await RecipeScope.read(context).addShoppingItem(name.text, quantity.text);
    }
    name.dispose();
    quantity.dispose();
  }
}

class AllergySettingsPage extends StatefulWidget {
  const AllergySettingsPage({super.key});

  @override
  State<AllergySettingsPage> createState() => _AllergySettingsPageState();
}

class _AllergySettingsPageState extends State<AllergySettingsPage> {
  static const common = ['卵', '乳', '小麦', 'えび', 'かに', 'そば', '落花生', 'くるみ'];
  late Set<String> _selected;
  final _other = TextEditingController();
  final _disliked = TextEditingController();
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final settings = RecipeScope.read(context).snapshot.allergySettings;
    _selected = settings.allergens.where(common.contains).toSet();
    _other.text = settings.allergens.where((value) => !common.contains(value)).join('、');
    _disliked.text = settings.dislikedFoods.join('、');
  }

  @override
  void dispose() {
    _other.dispose();
    _disliked.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('アレルギー・苦手な食材'),
      actions: [TextButton(onPressed: _save, child: const Text('保存'))],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SoftPanel(
          child: Text('AI提案では該当食材を避けます。ただし抽出漏れや製造時の混入まで保証できません。必ず元投稿と商品表示を確認してください。'),
        ),
        const SizedBox(height: 22),
        Text('アレルギー', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in common)
              FilterChip(
                label: Text(item),
                selected: _selected.contains(item),
                onSelected: (selected) => setState(() => selected ? _selected.add(item) : _selected.remove(item)),
              ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(controller: _other, decoration: const InputDecoration(labelText: 'その他（読点区切り）')),
        const SizedBox(height: 22),
        Text('苦手な食材', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        TextField(controller: _disliked, decoration: const InputDecoration(labelText: '例：パクチー、レバー')),
      ],
    ),
  );

  Future<void> _save() async {
    List<String> split(String value) => value
        .split(RegExp(r'[,，、\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    await RecipeScope.read(context).updateAllergySettings(
      AllergySettings(
        allergens: {..._selected, ...split(_other.text)}.toList(),
        dislikedFoods: split(_disliked.text),
      ),
    );
    if (mounted) Navigator.pop(context);
  }
}

class RecipeCollectionsPage extends StatelessWidget {
  const RecipeCollectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = RecipeScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('コレクション')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _create(context),
        child: const Icon(Icons.create_new_folder_outlined),
      ),
      body: controller.snapshot.collections.isEmpty
          ? const Center(child: Text('コレクションはまだありません'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final collection in controller.snapshot.collections)
                  ListTile(
                    leading: const Icon(Icons.folder_rounded, color: moss),
                    title: Text(collection.name),
                    subtitle: Text('${collection.recipeIds.length}件'),
                    trailing: IconButton(
                      tooltip: '削除',
                      onPressed: () => controller.deleteCollection(collection),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final input = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('コレクションを作成'),
        content: TextField(controller: input, autofocus: true, decoration: const InputDecoration(hintText: '例：平日の時短ごはん')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, input.text), child: const Text('作成')),
        ],
      ),
    );
    input.dispose();
    if (value != null && context.mounted) await RecipeScope.read(context).createCollection(value);
  }
}

class ImportStatusPage extends StatelessWidget {
  const ImportStatusPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = RecipeScope.of(context);
    final imports = List<RecipeImport>.of(controller.snapshot.imports)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return Scaffold(
      appBar: AppBar(title: const Text('取り込み状況')),
      body: imports.isEmpty
          ? const Center(child: Text('取り込み履歴はありません'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: imports.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, index) {
                final item = imports[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: SizedBox(
                    width: 54,
                    height: 54,
                    child: RecipeImage(path: item.coverImagePath, borderRadius: BorderRadius.circular(10)),
                  ),
                  title: Text(item.status.label),
                  subtitle: Text(item.message ?? item.sourceService ?? '共有投稿'),
                  trailing: item.status == RecipeImportStatus.failed
                      ? IconButton(
                          tooltip: '再試行',
                          onPressed: () => controller.retryImport(item),
                          icon: const Icon(Icons.refresh_rounded),
                        )
                      : null,
                );
              },
            ),
    );
  }
}
