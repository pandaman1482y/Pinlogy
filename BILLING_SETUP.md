# ツクレピ課金設定

## 商品ID

| 種類 | 商品ID | 価格 | 利用枠 |
|---|---|---:|---:|
| 自動更新（月額） | `tsukurepi_monthly_490` | ¥490/月 | 毎月30回 |
| 自動更新（年額） | `tsukurepi_annual_4980` | ¥4,980/年 | 毎月30回 |
| 消費型 | `tsukurepi_credits_20_400` | ¥400 | 20回追加 |

RevenueCatでは`default` Offeringを作り、月額・年額・追加20回の3商品を登録します。
月額と年額は同じEntitlement（例: `pro`）へ紐付けます。

## Supabase

```bash
npx supabase@latest db push

npx supabase@latest functions deploy analyze-post
npx supabase@latest functions deploy enqueue-analysis
npx supabase@latest functions deploy billing-status
npx supabase@latest functions deploy revenuecat-webhook --no-verify-jwt
```

Webhook用の十分に長いランダム文字列を作り、Supabaseへ保存します。

```bash
WEBHOOK_SECRET="$(openssl rand -hex 32)"
npx supabase@latest secrets set REVENUECAT_WEBHOOK_SECRET="$WEBHOOK_SECRET"
printf '%s\n' "$WEBHOOK_SECRET"
```

RevenueCat DashboardのWebhook URL:

```text
https://zgcvliipxfebnhbfswpc.supabase.co/functions/v1/revenuecat-webhook
```

Authorization headerには、上で表示された値の先頭へ`Bearer `を付けて登録します。

```text
Bearer <WEBHOOK_SECRET>
```

## Flutter

`config/revenuecat.json`を作り、RevenueCatの公開SDKキーを設定します。Secret APIキーは絶対にアプリへ入れません。

```json
{
  "REVENUECAT_IOS_API_KEY": "appl_xxxxxxxxxxxx",
  "REVENUECAT_ANDROID_API_KEY": "goog_xxxxxxxxxxxx"
}
```

```bash
flutter pub get
flutter run --release \
  --dart-define-from-file=config/supabase.json \
  --dart-define-from-file=config/revenuecat.json
```

## Sandboxで必ず確認する項目

1. 新規端末で残り3回と表示される
2. 成功解析だけ1回減る
3. 解析失敗、レシピ0件、キャンセルで回数が戻る
4. 同じジョブの再取得・内部リトライで追加消費されない
5. 月額購入後に30回になる
6. 年額購入後に30回になる
7. 追加20回購入で20回増える
8. 購入復元でサブスクリプションが戻る
9. 解約後も期限までは利用でき、期限後は追加購入分だけ残る

App Store申請前に、プライバシーポリシー、利用規約、自動更新条件、購入復元導線も確認してください。
