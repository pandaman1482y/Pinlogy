import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_scope.dart';
import '../../app/pinlogy_controller.dart';
import '../../core/errors.dart';
import '../../models/models.dart';
import '../../services/ai_analysis_consent.dart';
import '../../services/cloud_sync_service.dart';

class CloudSyncPage extends StatefulWidget {
  const CloudSyncPage({super.key, this.initialShareCode});

  final String? initialShareCode;

  @override
  State<CloudSyncPage> createState() => _CloudSyncPageState();
}

class _CloudSyncPageState extends State<CloudSyncPage> {
  bool busy = false;
  String? status;
  final codeController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool aiAnalysisEnabled = false;
  DateTime? lastSyncAt;
  StreamSubscription<void>? _authSubscription;

  @override
  void initState() {
    super.initState();
    codeController.text = widget.initialShareCode ?? '';
    AiAnalysisConsent().hasConsented().then((value) {
      if (mounted) setState(() => aiAnalysisEnabled = value);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _authSubscription ??= AppScope.read(context).cloud
        .watchAuthChanges()
        .listen((_) {
          if (mounted) {
            setState(() {});
            unawaited(_loadLastSync());
          }
        });
    unawaited(_loadLastSync());
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    codeController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final configured = controller.cloud.isConfigured;
    final signedIn = controller.cloud.hasRecoverableAccount;
    final hasCloudSession = controller.cloud.user != null;
    return Scaffold(
      appBar: AppBar(title: const Text('同期と共有')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _SyncHero(
            configured: configured,
            signedIn: signedIn,
            busy: busy,
            onSync: () => _sync(context),
            lastSyncAt: lastSyncAt,
          ),
          if (status != null) ...[
            const SizedBox(height: 8),
            _StatusMessage(message: status!),
          ],
          const SizedBox(height: 24),
          const _SectionTitle(title: 'マップを受け取る'),
          const SizedBox(height: 8),
          _Panel(
            child: Column(
              children: [
                TextField(
                  controller: codeController,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: '共有コードを入力',
                    prefixIcon: Icon(Icons.key_outlined),
                    border: InputBorder.none,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('自分のマップに追加'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: !configured || busy ? null : () => _accept(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Panel(
            child: ExpansionTile(
              leading: const Icon(Icons.link_off_outlined),
              title: const Text('発行済みリンクを管理'),
              subtitle: const Text('不要になった共有を停止できます'),
              children: [_activeShares(context, configured && hasCloudSession)],
            ),
          ),
          const SizedBox(height: 12),
          _Panel(
            child: ExpansionTile(
              leading: const Icon(Icons.travel_explore_outlined),
              title: const Text('公開マップから探す'),
              subtitle: const Text('見つけたマップを複製して編集できます'),
              children: [
                _publicMaps(context, controller, configured && hasCloudSession),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle(title: '自分のマップを送る'),
          const SizedBox(height: 4),
          const Text('共有ボタンから30日間有効なコードを送れます。'),
          const SizedBox(height: 8),
          _Panel(
            child: Column(
              children: controller.hub.snapshot.maps.indexed.map((entry) {
                final index = entry.$1;
                final map = entry.$2;
                return Column(
                  children: [
                    if (index > 0) const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: Text(
                        map.icon,
                        style: const TextStyle(fontSize: 24),
                      ),
                      title: Text(map.name),
                      subtitle: Text(
                        '${controller.placeCountForMap(map.id)}スポット',
                      ),
                      trailing: IconButton.filledTonal(
                        tooltip: '共有する',
                        onPressed: !configured || busy
                            ? null
                            : () => _shareMap(context, map),
                        icon: const Icon(Icons.ios_share_outlined, size: 20),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle(title: '設定'),
          const SizedBox(height: 8),
          _Panel(
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.auto_awesome_outlined),
                  value: aiAnalysisEnabled,
                  title: const Text('AIで投稿を高精度解析'),
                  subtitle: const Text('投稿文とOCR文字を安全に解析'),
                  onChanged: configured && !busy
                      ? (value) async {
                          await AiAnalysisConsent().setConsented(value);
                          if (mounted) {
                            setState(() => aiAnalysisEnabled = value);
                          }
                        }
                      : null,
                ),
                const Divider(height: 1, indent: 56),
                ExpansionTile(
                  leading: Icon(
                    signedIn
                        ? Icons.verified_user_outlined
                        : Icons.person_outline,
                  ),
                  title: Text(signedIn ? 'バックアップ用アカウント' : 'アカウントを設定'),
                  subtitle: Text(
                    signedIn
                        ? controller.cloud.user?.email ?? 'ログイン済み'
                        : '機種変更後もデータを復元できます',
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    if (!signedIn) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'メールアドレス',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          hintText: 'name@example.com',
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'パスワード',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(hintText: '8文字以上'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: !configured || busy
                                  ? null
                                  : () => _account(context, register: false),
                              child: const Text('ログイン'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.tonal(
                              onPressed: !configured || busy
                                  ? null
                                  : () => _account(context, register: true),
                              child: const Text('新規登録'),
                            ),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          children: [
                            TextButton(
                              onPressed: !configured || busy
                                  ? null
                                  : () => _resendConfirmation(context),
                              child: const Text('確認メールを再送'),
                            ),
                            TextButton(
                              onPressed: !configured || busy
                                  ? null
                                  : () => _resetPassword(context),
                              child: const Text('パスワードを忘れた場合'),
                            ),
                          ],
                        ),
                      ),
                      if (status != null) ...[
                        const SizedBox(height: 4),
                        _StatusMessage(message: status!),
                      ],
                    ] else ...[
                      const Text('このアカウントに同期すると、機種変更後もマップを復元できます。'),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: busy ? null : () => _signOut(context),
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('ログアウト'),
                      ),
                      TextButton.icon(
                        onPressed: busy ? null : () => _deleteAccount(context),
                        icon: const Icon(
                          Icons.person_remove_outlined,
                          color: Colors.red,
                        ),
                        label: const Text(
                          'アカウントを削除',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text('送信されるデータについて'),
            childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            children: const [
              Text(
                '同期対象：マップ名、店名、住所、座標、カテゴリ、訪問状態、元投稿URL。\n'
                '同期しない情報：個人メモ、投稿本文、OCR結果、解析結果、端末内画像。\n\n'
                'AI解析では投稿文と端末OCRの抽出候補をSupabase経由でOpenAIへ送信します。画像ファイル自体は送信しません。',
                style: TextStyle(height: 1.55),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _loadLastSync() async {
    try {
      final value = await AppScope.read(context).cloud.lastSyncAt();
      if (mounted) setState(() => lastSyncAt = value);
    } catch (_) {
      // The page already explains when cloud configuration is unavailable.
    }
  }

  Widget _publicMaps(
    BuildContext context,
    PinlogyController controller,
    bool configured,
  ) {
    if (!configured) {
      return const ListTile(title: Text('ログイン後に利用できます'));
    }
    return FutureBuilder<List<PublicMapSummary>>(
      future: controller.cloud.publicMaps(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return const ListTile(title: Text('公開マップを読み込めませんでした'));
        }
        final maps = snapshot.data ?? const [];
        if (maps.isEmpty) return const ListTile(title: Text('公開中のマップはまだありません'));
        return Column(
          children: maps
              .map(
                (item) => ListTile(
                  leading: Text(
                    item.icon,
                    style: const TextStyle(fontSize: 24),
                  ),
                  title: Text(item.name),
                  subtitle: Text(
                    '${item.placeCount}スポット${item.description.isEmpty ? '' : ' ・ ${item.description}'}',
                  ),
                  trailing: const Icon(Icons.copy_all_outlined),
                  onTap: busy ? null : () => _clonePublic(context, item),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _activeShares(BuildContext context, bool configured) {
    if (!configured) return const ListTile(title: Text('ログイン後に利用できます'));
    return FutureBuilder<List<ActiveMapShare>>(
      future: AppScope.read(context).cloud.activeMapShares(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return const ListTile(title: Text('共有リンクを読み込めませんでした'));
        }
        final shares = snapshot.data ?? const [];
        if (shares.isEmpty) {
          return const ListTile(title: Text('有効な共有リンクはありません'));
        }
        return Column(
          children: shares
              .map(
                (share) => ListTile(
                  title: Text(share.mapName),
                  subtitle: Text(
                    '有効期限 ${share.expiresAt.toLocal().year}/${share.expiresAt.toLocal().month}/${share.expiresAt.toLocal().day}',
                  ),
                  trailing: IconButton(
                    tooltip: '共有を停止',
                    icon: const Icon(Icons.link_off_outlined),
                    onPressed: busy
                        ? null
                        : () async {
                            await _run(
                              () => AppScope.read(
                                context,
                              ).cloud.revokeMapShare(share.token),
                              '共有リンクを停止しました',
                            );
                            if (mounted) setState(() {});
                          },
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Future<void> _sync(BuildContext context) async {
    final approved =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Supabaseと同期しますか？'),
            content: const Text(
              'マップ名、店名、住所、座標、カテゴリ、訪問状態、元投稿URLを設定済みのSupabaseへ送信します。'
              '個人メモ、投稿本文、OCR結果、解析結果、端末内画像は送信しません。クラウド取得時も端末だけのデータは削除しません。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('同期する'),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved || !mounted) return;
    await _run(
      () => AppScope.read(context).cloud.sync(AppScope.read(context).hub),
      '同期しました',
    );
    if (mounted) await _loadLastSync();
  }

  Future<void> _account(BuildContext context, {required bool register}) async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    if (!email.contains('@') || password.length < 8) {
      setState(() => status = 'メールアドレスと8文字以上のパスワードを入力してください');
      return;
    }
    await _run(
      () => register
          ? AppScope.read(context).cloud.registerAccount(email, password)
          : AppScope.read(context).cloud.signIn(email, password),
      register ? '確認メールのリンクを開くとPinlogyへ戻り、登録が完了します' : 'ログインしました',
    );
    passwordController.clear();
  }

  Future<void> _resetPassword(BuildContext context) async {
    final email = emailController.text.trim();
    if (!email.contains('@')) {
      setState(() => status = '先にメールアドレスを入力してください');
      return;
    }
    await _run(
      () => AppScope.read(context).cloud.sendPasswordReset(email),
      'パスワード再設定メールを送信しました',
    );
  }

  Future<void> _resendConfirmation(BuildContext context) async {
    final email = emailController.text.trim();
    if (!email.contains('@')) {
      setState(() => status = '先にメールアドレスを入力してください');
      return;
    }
    await _run(
      () => AppScope.read(context).cloud.resendConfirmation(email),
      '新しい確認メールを送信しました。最新のメールを開いてください',
    );
  }

  Future<void> _signOut(BuildContext context) async {
    await _run(
      () => AppScope.read(context).cloud.signOut(),
      'ログアウトしました。端末内のデータは残っています',
    );
  }

  Future<void> _shareMap(BuildContext context, PinMap map) async {
    final controller = AppScope.read(context);
    final cloud = controller.cloud;
    await _run(() async {
      // 共有直前に最新の場所と安全な元投稿URLを反映し、受取側の欠落を防ぐ。
      await cloud.sync(controller.hub);
      final code = await cloud.createShareCode(map.id);
      final link = cloud.mapShareUri(code);
      await SharePlus.instance.share(
        ShareParams(
          subject: '${map.name} - Pinlogy',
          text:
              'Pinlogyで「${map.name}」を受け取る：\n$link\n\n'
              'リンクが開かない場合の共有コード：$code\n有効期限は30日です。',
        ),
      );
    }, '共有コードを発行しました');
  }

  Future<void> _accept(BuildContext context) async {
    final code = codeController.text.trim();
    if (code.isEmpty) return;
    await _run(
      () => AppScope.read(
        context,
      ).cloud.acceptShareCode(AppScope.read(context).hub, code),
      '共有マップを追加しました',
    );
    codeController.clear();
  }

  Future<void> _clonePublic(BuildContext context, PublicMapSummary map) async {
    await _run(
      () => AppScope.read(
        context,
      ).cloud.clonePublicMap(AppScope.read(context).hub, map.id),
      '「${map.name}」を自分用に複製しました',
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('アカウントを削除しますか？'),
        content: const Text(
          'Supabase上のアカウント、所有マップ、場所、共有情報を完全に削除します。'
          'この端末に保存されたデータは残ります。この操作は元に戻せません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('完全に削除'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    await _run(
      () => AppScope.read(context).cloud.deleteAccount(),
      'アカウントを削除しました',
    );
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() {
      busy = true;
      status = null;
    });
    try {
      await action();
      if (mounted) setState(() => status = success);
    } catch (error) {
      if (mounted) setState(() => status = toUserMessage(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _SyncHero extends StatelessWidget {
  const _SyncHero({
    required this.configured,
    required this.signedIn,
    required this.busy,
    required this.onSync,
    required this.lastSyncAt,
  });

  final bool configured;
  final bool signedIn;
  final bool busy;
  final VoidCallback onSync;
  final DateTime? lastSyncAt;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  configured
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'クラウド同期',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      !configured
                          ? 'Supabaseが未設定です'
                          : signedIn
                          ? 'アカウントに接続済み'
                          : 'この端末用に接続できます',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (lastSyncAt != null) ...[
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 17),
                const SizedBox(width: 7),
                Text(
                  '最終同期 ${_formatSyncTime(lastSyncAt!)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          const Text('必要な時だけ手動で同期します。端末内のデータが勝手に削除されることはありません。'),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: configured && !busy ? onSync : null,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(busy ? '同期中…' : '今すぐ同期'),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatSyncTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: .55),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(message, textAlign: TextAlign.center),
  );
}
