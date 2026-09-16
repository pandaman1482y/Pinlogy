# Recipe App デプロイ手順

## Supabase

```sh
cd /Users/moritayuuya/Documents/GitHub/Pinlogy
npx supabase@latest login
npx supabase@latest link --project-ref zgcvliipxfebnhbfswpc
npx supabase@latest db push
npx supabase@latest functions deploy analyze-post
npx supabase@latest functions deploy enqueue-analysis
npx supabase@latest functions deploy recipe-assistant
```

`401 Unauthorized` の場合は `login` でブラウザ認証し直し、`link` から再開します。Supabase Secretsに次を設定します。

- `OPENAI_API_KEY`
- `OPENAI_MODEL`（任意）
- `BRIGHT_DATA_API_TOKEN`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`

Bright DataはEdge Functionログの `bright_data_instagram_snapshot_resolved images=9` で確認します。

## Firebase / Push

- `ios/Runner/GoogleService-Info.plist` の `BUNDLE_ID` を `com.pinlogy.pinlogy` にします。
- Firebase Consoleに APNs認証キー、Key ID、Apple Team IDを登録します。
- XcodeのRunnerに Push Notifications を追加し、RunnerとShare ExtensionのApp Groupを同じ値にします。
- 新規インストール後は一度アプリを起動し、通知許可とFCM tokenを取得します。
- マイページの通知診断とテスト通知を実行します。

## iPhone実機

```sh
cd /Users/moritayuuya/Documents/GitHub/Pinlogy
flutter clean
flutter pub get
flutter run --release \
  -d 00008120-000255811490A01E \
  --dart-define-from-file=config/supabase.json
```

別Apple Teamで署名された同Bundle IDの旧アプリが端末に残っている場合は、旧アプリを削除してから再実行します。

## 受け入れ確認

1. アプリを一度起動し、通知をONにします。
2. Instagramの複数画像投稿を共有し、アプリを開かずに待ちます。
3. ジョブが `queued -> processing -> completed` になることを確認します。
4. 完了通知後にアプリを開き、仮カードがレシピに置き換わることを確認します。
5. 各候補にそれぞれの根拠画像が表示されることを確認します。
