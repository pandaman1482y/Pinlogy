import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

enum LegalDocument { terms, privacy }

extension LegalDocumentDetails on LegalDocument {
  String get title => switch (this) {
    LegalDocument.terms => '利用規約',
    LegalDocument.privacy => 'プライバシーポリシー',
  };

  String get assetPath => switch (this) {
    LegalDocument.terms => 'assets/legal/terms.md',
    LegalDocument.privacy => 'assets/legal/privacy_policy.md',
  };
}

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({required this.document, super.key});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(document.title)),
    body: FutureBuilder<String>(
      future: _loadDocument(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return const Center(child: Text('文書を読み込めませんでした'));
        }
        return SelectionArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
            children: _buildBlocks(context, snapshot.data!),
          ),
        );
      },
    ),
  );

  Future<String> _loadDocument() async {
    final original = await rootBundle.loadString(document.assetPath);
    final supplement = document == LegalDocument.terms
        ? _accountBillingTerms
        : _accountBillingPrivacy;
    return '$original\n\n$supplement';
  }

  static List<Widget> _buildBlocks(BuildContext context, String source) {
    final widgets = <Widget>[];
    for (final rawLine in source.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty) {
        widgets.add(const SizedBox(height: 8));
      } else if (line.startsWith('# ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              line.substring(2),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        );
      } else if (line.startsWith('## ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 5),
            child: Text(
              line.substring(3),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        );
      } else if (line.startsWith('### ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 3),
            child: Text(
              line.substring(4),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        );
      } else {
        final isBullet = line.startsWith('- ');
        widgets.add(
          Padding(
            padding: EdgeInsets.only(left: isBullet ? 8 : 0, bottom: 4),
            child: Text(
              isBullet ? '• ${line.substring(2)}' : line,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.65, color: ink),
            ),
          ),
        );
      }
    }
    return widgets;
  }
}

class LegalConsentCheckbox extends StatefulWidget {
  const LegalConsentCheckbox({
    required this.initiallyAccepted,
    required this.onChanged,
    super.key,
  });

  final bool initiallyAccepted;
  final ValueChanged<bool> onChanged;

  @override
  State<LegalConsentCheckbox> createState() => _LegalConsentCheckboxState();
}

class _LegalConsentCheckboxState extends State<LegalConsentCheckbox> {
  late bool _accepted;

  @override
  void initState() {
    super.initState();
    _accepted = widget.initiallyAccepted;
  }

  Future<void> _open(LegalDocument document) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentPage(document: document),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 2,
        children: [
          TextButton(
            onPressed: () => _open(LegalDocument.terms),
            child: const Text('利用規約'),
          ),
          const Text('と'),
          TextButton(
            onPressed: () => _open(LegalDocument.privacy),
            child: const Text('プライバシーポリシー'),
          ),
        ],
      ),
      CheckboxListTile(
        value: _accepted,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('利用規約とプライバシーポリシーに同意します'),
        onChanged: (value) {
          final accepted = value == true;
          setState(() => _accepted = accepted);
          widget.onChanged(accepted);
        },
      ),
    ],
  );
}

const _accountBillingTerms = r"""
## 課金・解析枠・アカウント削除に関する補足（2026年10月13日）
本補足は、解析枠の更新、アカウント削除、初回無料枠、購入復元に関する従来の記載を更新します。同じ事項について記載が異なる場合は、本補足を適用します。
- 初回無料の解析3回は初回利用者向けの特典です。同一利用者として確認できる場合、アカウントの削除・再登録、ログインし直しによって再付与されません。使い切っていない無料枠もアカウント削除時に失効します。
- アカウントを削除するとレシピ・解析履歴などのアカウントデータは削除され、元に戻せません。未使用の追加購入回数は失効し、再登録後の購入復元では戻りません。返金の可否は適用法令および購入先ストアの手続に従います。
- アカウント削除はApp Store・Google Playの定期購入の解約ではありません。継続課金を止めるには、購入したストアのサブスクリプション管理画面から別途解約してください。解約していなくてもアカウントの即時削除を選択できます。
- 有効な定期購入は、再登録後に購入に使ったストアアカウントで「購入を復元」してください。レシピなどの削除済みデータは復元されません。同じ回数付与期間で使用した解析回数はリセットされず、未使用分だけを利用できます。
- 購入復元はストア・課金管理サービスによる確認を必要とします。反映が遅れる場合や復元できない場合は、購入を繰り返さず、時間をおいて再試行するかアプリ内の問い合わせ先へご連絡ください。
- 無料枠の重複付与防止、購入復元、二重付与防止のため、アカウント削除後も必要な識別記録・課金利用記録を保持します。詳細はプライバシーポリシーをご確認ください。
- 月額プランの解析30回は、ストアで確認された契約期間ごとに更新します。更新通知が早く届いても、新しい契約期間の開始日時までは更新しません。更新が確認できない場合、日付が変わっただけで新しい30回は付与されません。
- 年額プランは、ストアで確認された年契約の開始日時を基準に毎月30回へ更新します。月の計算は日本時間で行い、対応する日がない月はその月の末日、以後は元の開始日に戻ります。契約有効期限を超えて付与しません。
- 未使用の月間枠は繰り越しません。解約の取消し、購入復元、アカウント削除・再登録で同じ期間の使用回数はリセットされません。ストアの更新確認・通信状況によって反映に時間がかかる場合があります。
- 本サービスの解析枠は毎月1日午前9時に一律更新する方式ではありません。従来の暦月更新に関する記載がある場合は本項の契約期間基準を適用します。

""";

const _accountBillingPrivacy = r"""
## アカウント削除後に保持する課金関連記録（2026年10月12日）
本補足は、アカウント削除後の情報保持に関する従来の記載を更新します。同じ事項について記載が異なる場合は、本補足を適用します。
- アカウント削除時に、レシピ、解析履歴、保存画像などを削除します。ただし、以下の目的に必要な記録は削除対象から除きます。
- 初回無料枠の重複付与を防ぐため、Apple・Google等のログイン識別値および確認済みメールアドレスから生成する鍵付きハッシュ値と、無料枠の付与履歴を保持します。これらは元のメールアドレス等をそのまま保存したものではありませんが、同一利用者の判定に使用する識別記録です。
- 有効な定期購入の復元および解析回数の二重付与防止のため、ハッシュ化した課金アカウント・購入識別記録、プラン、有効期限、契約期間・回数付与期間の開始と終了日時、期間別の使用回数、処理済み課金イベントの記録を保持します。
- これらの記録は無料枠の重複付与防止、購入・利用権の管理、不正利用防止および必要な問い合わせ対応に使用します。無料枠の履歴は当該特典を提供し重複付与防止が必要な期間、購入・課金記録は購入管理や適用法令への対応に必要な期間保持します。目的がなくなった記録は削除または個人との関連付けを解消します。
- App Store・Google PlayおよびRevenueCat側の購入・契約記録は、それぞれのサービスの規約・プライバシーポリシーに従って管理されます。ツクレピのアカウント削除だけでは、これらのサービス側の契約は解約されません。
""";
