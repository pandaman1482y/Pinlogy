# Pinlogy Recipe

Instagram / TikTok などの料理投稿を共有すると、画像・投稿文・OCRを照合し、再現できる構造化レシピとして保存する Flutter アプリです。

## 主な機能

- SNS投稿の共有、URL貼り付け、手動作成
- 画像・キャプション・OCRからのレシピ抽出
- 本体、タレ、出汁などを1レシピ内でパート分け
- 1投稿に複数料理がある場合の選択保存
- 2列サムネイル、検索・絞り込み、関連レシピ
- 人数変更による分量換算、買い物リスト、調理モード
- 保存済みレシピを根拠にする AI 相談
- Apple / Google ログインとクラウド同期
- バックグラウンド解析ジョブ、完了通知、再試行・キャンセル

Instagram の多画像取得は既存の Bright Data snapshot 経路を維持しています。元動画は保持せず、元URL・トップ画像・構造化データを保存します。

## 起動

`config/supabase.json.example` を `config/supabase.json` にコピーし、Supabase URL と公開可能な anon/publishable key を設定します。Service Role Key は入れないでください。

```sh
flutter pub get
flutter run --dart-define-from-file=config/supabase.json
```

## バックエンド

```sh
npx supabase@latest db push
npx supabase@latest functions deploy analyze-post
npx supabase@latest functions deploy enqueue-analysis
npx supabase@latest functions deploy recipe-assistant
```

詳細は `docs/RECIPE_APP_DEPLOY.md`、確定仕様は `docs/RECIPE_APP_SPEC.md` を参照してください。

## 検証

```sh
flutter analyze
flutter test
```

AI抽出は不完全です。食物アレルギーは元投稿と商品表示を必ず確認してください。標準解析は3分以内の投稿を基準とします。
