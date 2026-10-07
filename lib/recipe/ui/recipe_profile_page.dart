import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../models/recipe_models.dart';
import '../recipe_scope.dart';
import 'recipe_widgets.dart';
import '../../services/notification_service.dart';
import 'billing_page.dart';
import '../../services/billing_service.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/legal_consent_service.dart';
import 'legal_document_page.dart';

class RecipeProfilePage extends StatefulWidget {
  const RecipeProfilePage({super.key});

  @override
  State<RecipeProfilePage> createState() => _RecipeProfilePageState();
}

class _RecipeProfilePageState extends State<RecipeProfilePage> {
  DateTime? _lastSyncAt;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadLastSync();
  }

  Future<void> _loadLastSync() async {
    try {
      final value = await RecipeScope.read(context).legacy.cloud.lastSyncAt();
      if (mounted && value != _lastSyncAt) setState(() => _lastSyncAt = value);
    } catch (_) {
      // Supabase未設定の開発環境では端末保存表示を継続する。
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = RecipeScope.of(context);
    final user = controller.legacy.cloud.user;
    final pending = controller.activeImports;
    final reviewCount = pending
        .where(
          (item) =>
              item.status == RecipeImportStatus.awaitingSelection ||
              item.status == RecipeImportStatus.failed,
        )
        .length;
    return Scaffold(
      appBar: AppBar(title: const Text('マイページ')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          _AccountPlanCard(
            email: user?.email,
            isAnonymous: user?.isAnonymous ?? true,
            recipeCount: controller.savedRecipes.length,
            cookedCount: controller.snapshot.cookingRecords.length,
            lastSyncAt: _lastSyncAt,
            onAccountTap: () => user == null || user.isAnonymous
                ? _showLoginOptions(context)
                : _showAccountActions(context),
            onPlanTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BillingPage()),
            ),
          ),
          const SizedBox(height: 24),
          Text('レシピ管理', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _GroupedCard(
            children: [
              _MenuRow(
                icon: Icons.shopping_cart_outlined,
                title: '買い物リスト',
                value:
                    '${controller.snapshot.shoppingItems.where((item) => !item.checked).length}件',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ShoppingListPage(),
                  ),
                ),
              ),
              _MenuRow(
                icon: Icons.folder_outlined,
                title: 'コレクション',
                value: '${controller.snapshot.collections.length}個',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RecipeCollectionsPage(),
                  ),
                ),
              ),
              _MenuRow(
                icon: Icons.cloud_sync_outlined,
                title: '取り込み状況',
                value: reviewCount > 0
                    ? '要確認 $reviewCount件'
                    : pending.isNotEmpty
                    ? '処理中 ${pending.length}件'
                    : '完了',
                statusColor: reviewCount > 0
                    ? warningColor
                    : pending.isNotEmpty
                    ? moss
                    : null,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ImportStatusPage(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text('設定', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _GroupedCard(
            children: [
              _MenuRow(
                icon: Icons.health_and_safety_outlined,
                title: 'アレルギー・苦手な食材',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AllergySettingsPage(),
                  ),
                ),
              ),
              _MenuRow(
                icon: Icons.notifications_outlined,
                title: '通知設定',
                value: controller.notificationsEnabled ? 'オン' : 'オフ',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NotificationSettingsPage(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text('サポート', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _GroupedCard(
            children: [
              _MenuRow(
                title: 'お知らせ',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AnnouncementsPage(),
                  ),
                ),
              ),
              _MenuRow(
                title: 'ヘルプ・お問い合わせ',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const HelpSupportPage(),
                  ),
                ),
              ),
              _MenuRow(
                title: '注意事項',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ImportantNotesPage(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showLoginOptions(BuildContext context) async {
    final legalConsent = LegalConsentService();
    var accepted = await legalConsent.hasAcceptedCurrentVersion();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            2,
            20,
            20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                child: Container(
                  width: 54,
                  height: 54,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: const BoxDecoration(
                    color: mintSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cloud_done_outlined,
                    color: mossDeep,
                    size: 28,
                  ),
                ),
              ),
              Text(
                'レシピを安全に引き継ぐ',
                textAlign: TextAlign.center,
                style: Theme.of(sheetContext).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'ログインすると保存したレシピを同期し、機種変更後も引き継げます。',
                textAlign: TextAlign.center,
                style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              LegalConsentCheckbox(
                initiallyAccepted: accepted,
                onChanged: (value) async {
                  setSheetState(() => accepted = value);
                  if (value) await legalConsent.acceptCurrentVersion();
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: accepted
                      ? () {
                          Navigator.pop(sheetContext);
                          _signIn(context, apple: true);
                        }
                      : null,
                  icon: const Icon(Icons.apple, size: 24),
                  label: const Text('Appleで続ける'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: accepted
                      ? () {
                          Navigator.pop(sheetContext);
                          _signIn(context, apple: false);
                        }
                      : null,
                  icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                  label: const Text('Googleで続ける'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(
                      sheetContext,
                    ).colorScheme.onSurface,
                    side: BorderSide(
                      color: Theme.of(sheetContext).colorScheme.outlineVariant,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAccountActions(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_sync_rounded),
                title: const Text('今すぐ同期'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _syncCloud(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('ログアウト'),
                subtitle: const Text('端末内のレシピは残ります'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await RecipeScope.read(context).legacy.cloud.signOut();
                  if (context.mounted) {
                    setState(() => _lastSyncAt = null);
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_forever_rounded,
                  color: Colors.red,
                ),
                title: const Text(
                  'アカウントを削除',
                  style: TextStyle(color: Colors.red),
                ),
                subtitle: const Text('クラウドデータと残り回数を削除します'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDeleteAccount(context);
                },
              ),
            ],
          ),
        ),
      );

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      barrierDismissible: false,
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('アカウントを削除しますか？'),
        content: const Text(
          'クラウド上のレシピ、解析履歴、残り回数は完全に削除され、元に戻せません。'
          '無料3回は再登録しても復活しません。\n\n'
          'App StoreまたはGoogle Playの定期購入は自動解約されません。削除前にストアで解約してください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final controller = RecipeScope.read(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 18),
            Expanded(child: Text('アカウントを削除しています…')),
          ],
        ),
      ),
    );
    try {
      await controller.legacy.cloud.deleteAccount();
      await controller.clearAfterAccountDeletion();
      await BillingService.instance.syncAuthenticatedUser();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => _lastSyncAt = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('アカウントを削除しました。利用を続けるには再度ログインしてください。')),
      );
    } on CloudSignInCancelled {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (error) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  Future<void> _signIn(BuildContext context, {required bool apple}) async {
    final cloud = RecipeScope.read(context).legacy.cloud;
    try {
      apple ? await cloud.signInWithApple() : await cloud.signInWithGoogle();
      if (!context.mounted) return;
      if (cloud.user != null && cloud.user?.isAnonymous != true) {
        setState(() {});
        await _loadLastSync();
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ログインしました。レシピを同期します。')));
      }
    } on CloudSignInCancelled {
      return;
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ログインを開始できませんでした: $error')));
    }
  }

  Future<void> _syncCloud(BuildContext context) async {
    final controller = RecipeScope.read(context);
    try {
      await controller.syncCloud();
      await _loadLastSync();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('レシピを同期しました')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('同期できませんでした: $error')));
    }
  }
}

class _GroupedCard extends StatelessWidget {
  const _GroupedCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: mintSoft,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: borderSubtle),
    ),
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index < children.length - 1) const Divider(height: 1, indent: 52),
        ],
      ],
    ),
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    this.icon,
    required this.title,
    this.value,
    this.statusColor,
    required this.onTap,
  });
  final IconData? icon;
  final String title;
  final String? value;
  final Color? statusColor;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
    leading: icon == null
        ? null
        : SizedBox(width: 24, child: Icon(icon, color: mossDeep, size: 23)),
    title: Text(title),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (statusColor != null) ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
        ],
        if (value != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Text(
              value!,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right_rounded, size: 20),
      ],
    ),
    onTap: onTap,
  );
}

class _AccountPlanCard extends StatelessWidget {
  const _AccountPlanCard({
    required this.email,
    required this.isAnonymous,
    required this.recipeCount,
    required this.cookedCount,
    required this.lastSyncAt,
    required this.onAccountTap,
    required this.onPlanTap,
  });
  final String? email;
  final bool isAnonymous;
  final int recipeCount;
  final int cookedCount;
  final DateTime? lastSyncAt;
  final VoidCallback onAccountTap;
  final VoidCallback onPlanTap;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: BillingService.instance,
    builder: (context, _) {
      final status = BillingService.instance.status;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: mintSoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderSubtle),
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              onTap: onAccountTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 25,
                      backgroundColor: mint,
                      child: Icon(
                        Icons.person_outline_rounded,
                        color: mossDeep,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAnonymous
                                ? '端末に保存中'
                                : (email?.trim().isNotEmpty == true
                                      ? email!
                                      : 'ログイン済み'),
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isAnonymous
                                ? 'ログインすると端末間で同期できます'
                                : _syncLabel(lastSyncAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '$recipeCountレシピ・$cookedCount回作った',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isAnonymous ? 'ログイン' : 'アカウント',
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: mossDeep),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: mossDeep,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            InkWell(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(20),
              ),
              onTap: onPlanTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '現在の利用プラン',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            _planLabel(status?.plan),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '解析あと${status?.remaining ?? 0}回',
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: mossDeep),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: mossDeep,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  static String _planLabel(String? plan) => switch (plan) {
    'monthly' => '月額プラン',
    'annual' => '年額プラン',
    _ => '無料プラン',
  };
  static String _syncLabel(DateTime? value) {
    if (value == null) return '同期可能';
    final local = value.toLocal();
    return '同期済み ${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});
  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  NotificationDiagnostics? _status;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final value = await PinlogyNotificationService.instance.diagnostics();
    if (mounted) setState(() => _status = value);
  }

  @override
  Widget build(BuildContext context) {
    final controller = RecipeScope.of(context);
    final permission = _status?.permission ?? '確認中';
    return Scaffold(
      appBar: AppBar(title: const Text('通知設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _GroupedCard(
            children: [
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                title: const Text('解析完了の通知'),
                subtitle: const Text('解析が完了したときにお知らせします'),
                value: controller.notificationsEnabled,
                onChanged: (value) => _setEnabled(context, value),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('端末の通知許可', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SoftPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  permission,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  permission == '拒否'
                      ? '端末の設定でツクレピの通知を許可してください。'
                      : '通知が届かない場合は、端末側でもツクレピの通知が許可されているか確認してください。',
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _openSystemSettings,
                  child: const Text('端末の設定を開く'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setEnabled(BuildContext context, bool value) async {
    final accepted = await RecipeScope.read(
      context,
    ).setNotificationsEnabled(value);
    await _refresh();
    if (!context.mounted) return;
    if (!accepted && value)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('通知を有効にできませんでした。端末の通知設定を確認してください。')),
      );
  }

  Future<void> _openSystemSettings() async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse('app-settings:'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('端末の「設定」からツクレピの通知を開いてください。')),
      );
    }
  }
}

class AnnouncementsPage extends StatelessWidget {
  const AnnouncementsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('お知らせ')),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 42,
              color: secondaryInk,
            ),
            SizedBox(height: 12),
            Text('現在のお知らせはありません'),
            SizedBox(height: 4),
            Text('新機能やメンテナンス情報がある場合に表示します。', textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ヘルプ・お問い合わせ')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SoftPanel(child: Text('お問い合わせ先は現在未設定です。公開前に正式な連絡先を設定してください。')),
        const SizedBox(height: 18),
        Text('法的情報', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _GroupedCard(
          children: [
            _MenuRow(
              title: '利用規約',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const LegalDocumentPage(document: LegalDocument.terms),
                ),
              ),
            ),
            _MenuRow(
              title: 'プライバシーポリシー',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const LegalDocumentPage(document: LegalDocument.privacy),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class ImportantNotesPage extends StatelessWidget {
  const ImportantNotesPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('注意事項')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        _NoticeSection(
          title: 'AI解析について',
          body: 'AI解析では、材料・分量・調理手順などに誤りや抜けが生じる場合があります。調理前に必ず元投稿の内容を確認してください。',
        ),
        _NoticeSection(
          title: 'アレルギー・苦手な食材',
          body:
              'アレルギーや苦手な食材の検出・注意表示は確認を補助する機能であり、完全な検出を保証するものではありません。使用する食品の原材料や商品表示も必ず確認してください。',
        ),
        _NoticeSection(
          title: '加熱・保存について',
          body:
              '加熱時間や保存期間は、食材の状態、調理器具、室温や保存環境によって変わります。食材の状態を確認し、安全を優先して調整してください。',
        ),
        _NoticeSection(
          title: '投稿の権利について',
          body:
              '元投稿のレシピ、文章、画像、動画などの権利は、それぞれの権利者に帰属します。保存した内容は元投稿への確認を補助する目的で利用してください。',
        ),
      ],
    ),
  );
}

class _NoticeSection extends StatelessWidget {
  const _NoticeSection({required this.title, required this.body});
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(body),
        ],
      ),
    ),
  );
}

/// 通常のマイページには表示せず、開発・サポート時だけ直接開く診断画面。
class NotificationDiagnosticsPage extends StatelessWidget {
  const NotificationDiagnosticsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('通知診断')),
    body: FutureBuilder<NotificationDiagnostics>(
      future: PinlogyNotificationService.instance.diagnostics(),
      builder: (context, snapshot) {
        final status = snapshot.data;
        if (status == null)
          return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              title: const Text('Firebase'),
              trailing: Text(status.firebaseReady ? '接続済み' : '未接続'),
            ),
            ListTile(
              title: const Text('端末の通知権限'),
              trailing: Text(status.permission),
            ),
            ListTile(
              title: const Text('通知トークン'),
              trailing: Text(status.tokenReady ? '取得済み' : '未取得'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final sent = await PinlogyNotificationService.instance
                    .sendTestNotification();
                if (context.mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(sent ? 'テスト通知を送信しました' : 'テスト通知を送信できませんでした'),
                    ),
                  );
              },
              child: const Text('テスト通知'),
            ),
          ],
        );
      },
    ),
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
            TextButton(
              onPressed: controller.clearPurchasedItems,
              child: const Text('購入済みを削除'),
            ),
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
                    style: TextStyle(
                      decoration: item.checked
                          ? TextDecoration.lineThrough
                          : null,
                    ),
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
      barrierDismissible: false,
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('買うものを追加'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '品名'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: quantity,
              decoration: const InputDecoration(labelText: '数量（任意）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('追加'),
          ),
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
    _other.text = settings.allergens
        .where((value) => !common.contains(value))
        .join('、');
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
          child: Text(
            'AI提案では該当食材を避けます。ただし抽出漏れや製造時の混入まで保証できません。必ず元投稿と商品表示を確認してください。',
          ),
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
                onSelected: (selected) => setState(
                  () => selected ? _selected.add(item) : _selected.remove(item),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _other,
          decoration: const InputDecoration(labelText: 'その他（読点区切り）'),
        ),
        const SizedBox(height: 22),
        Text('苦手な食材', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _disliked,
          decoration: const InputDecoration(labelText: '例：パクチー、レバー'),
        ),
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
      barrierDismissible: false,
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('コレクションを作成'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例：平日の時短ごはん'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, input.text),
            child: const Text('作成'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value != null && context.mounted)
      await RecipeScope.read(context).createCollection(value);
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
                    child: RecipeImage(
                      path: item.coverImagePath,
                      borderRadius: BorderRadius.circular(10),
                    ),
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
