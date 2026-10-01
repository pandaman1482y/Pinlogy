import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/theme.dart';
import '../../services/billing_service.dart';
import 'recipe_widgets.dart';

class BillingPage extends StatelessWidget {
  const BillingPage({super.key});

  static const monthlyId = 'tsukurepi_monthly_490';
  static const annualId = 'tsukurepi_annual_4980';
  static const creditsId = 'tsukurepi_credits_20_400';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: BillingService.instance,
    builder: (context, _) {
      final billing = BillingService.instance;
      final status = billing.status;
      return Scaffold(
        appBar: AppBar(title: const Text('利用プラン')),
        body: RefreshIndicator(
          onRefresh: billing.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              SoftPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '残り ${status?.remaining ?? '—'} 回',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(_planLabel(status?.plan)),
                    if ((status?.bonusCredits ?? 0) > 0)
                      Text(
                        '追加購入分 ${status!.bonusCredits}回を含みます',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('プラン', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              _PlanCard(
                title: '月額プラン',
                price: '月額 ¥490',
                detail: '毎月30回まで解析',
                package: billing.packageFor(monthlyId),
                active: status?.plan == 'monthly',
              ),
              _PlanCard(
                title: '年額プラン',
                price: '年額 ¥4,980',
                detail: '毎月30回まで解析',
                package: billing.packageFor(annualId),
                active: status?.plan == 'annual',
              ),
              _PlanCard(
                title: '追加20回',
                price: '¥400',
                detail: '使い切り・有効期限なし',
                package: billing.packageFor(creditsId),
                active: false,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _restore(context),
                child: const Text('購入を復元'),
              ),
              const SizedBox(height: 12),
              const Text(
                '解析に成功してレシピが作成された場合のみ1回消費します。失敗・レシピ未検出・サーバーエラーでは消費されません。定期購入はApp StoreまたはGoogle Playの設定から解約できます。',
              ),
              if (billing.error != null) ...[
                const SizedBox(height: 12),
                Text(billing.error!, style: const TextStyle(color: errorColor)),
              ],
            ],
          ),
        ),
      );
    },
  );

  static String _planLabel(String? plan) => switch (plan) {
    'monthly' => '月額プラン利用中',
    'annual' => '年額プラン利用中',
    _ => '無料枠（初回3回）',
  };

  static Future<void> _restore(BuildContext context) async {
    try {
      await BillingService.instance.restore();
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('購入情報を復元しました')));
    } catch (error) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('復元できませんでした: $error')));
    }
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.price,
    required this.detail,
    required this.package,
    required this.active,
  });
  final String title;
  final String price;
  final String detail;
  final Package? package;
  final bool active;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  package?.storeProduct.priceString ?? price,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: mossDeep),
                ),
                Text(detail),
              ],
            ),
          ),
          FilledButton(
            onPressed: active || package == null ? null : () => _buy(context),
            child: Text(active ? '利用中' : '購入'),
          ),
        ],
      ),
    ),
  );

  Future<void> _buy(BuildContext context) async {
    try {
      await BillingService.instance.purchase(package!);
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('購入が完了しました')));
    } catch (error) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('購入を完了できませんでした: $error')));
    }
  }
}
