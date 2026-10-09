import 'package:flutter_test/flutter_test.dart';
import 'package:pinlogy/services/billing_service.dart';

void main() {
  test('無料・プラン・追加購入の残高を別々に読み込む', () {
    final status = BillingStatus.fromJson({
      'plan': 'monthly',
      'remaining': 53,
      'free_remaining': 3,
      'plan_remaining': 30,
      'bonus_credits': 20,
      'entitlement_expires_at': '2026-11-09T00:00:00Z',
    });

    expect(status.plan, 'monthly');
    expect(status.remaining, 53);
    expect(status.freeRemaining, 3);
    expect(status.planRemaining, 30);
    expect(status.bonusCredits, 20);
  });
}
