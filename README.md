# Pinlogy

## 公開ビルドの経路設定

アプリ内経路は HTTPS のOSRM互換APIを利用します。公開OSRMデモはSLAがないため、公開版では自前運用または契約した経路サービスのURLを指定してください。

```bash
flutter build appbundle --release \
  --dart-define=ROUTING_API_BASE_URL=https://YOUR_ROUTING_ENDPOINT \
  --dart-define=MAP_TILE_URL_TEMPLATE=https://YOUR_TILE_ENDPOINT/{z}/{x}/{y}.png \
  --dart-define=MAP_TILE_ATTRIBUTION='© OpenStreetMap contributors'
```

URL未設定時とAPI障害時は、Google MapsまたはApple Mapsの外部ナビへフォールバックします。現在地と目的地は、ユーザーが経路表示を操作して初回同意した後にだけ送信され、Pinlogy内には経路履歴を保存しません。公開前にプライバシーポリシーへ利用する経路事業者名、送信情報、保持期間を明記してください。

## Supabase無料枠の設定

1. Supabaseでプロジェクトを作成し、AuthenticationのEmail/PasswordとAnonymous Sign-Insを有効化
2. SQL Editorで `001_initial.sql`〜`006_release_hardening.sql` を番号順に適用
3. AI解析を使う場合は `supabase functions deploy analyze-post` を実行し、Supabase Secretに `OPENAI_API_KEY` を設定

AI解析はユーザーがアプリ内で明示的に有効化した場合だけ使われます。未同意・未設定・障害時は端末OCRとローカル解析へ戻ります。OpenAI APIキーをFlutterアプリへ埋め込まないでください。
3. `config/supabase.json.example` を `config/supabase.json` にコピーし、URLとPublishable Keyを設定

```bash
flutter run --dart-define-from-file=config/supabase.json
```

公開ビルドも同じ設定ファイルを利用できます。

```bash
flutter build appbundle --release \
  --dart-define-from-file=config/supabase.json
```

`config/supabase.json` はGit管理対象外です。SupabaseのService Role Keyは絶対に入れず、クライアント公開可能なPublishable Key（旧Anon Key）のみを設定してください。

同期は保存済み画面右上の雲アイコンから手動実行します。メモ、元投稿、画像はクラウドへ送信しません。取得データは端末データへID単位で統合し、端末だけのデータを削除しません。

機種変更・再インストール後の復元には、同期画面でメールアドレスとパスワードのアカウントを作成してください。匿名利用は共有コードの受け取りを試す用途には使えますが、端末を失った後の本人確認には利用できません。

SNSで見つけた場所を、投稿ごと自分のマップに残すFlutterアプリです。

## 現在の実装

ローカル永続化（SharedPreferences）を中心に、APIキーなしでも動作する初期公開版を実装しています。

- マップの作成・編集・削除
- 場所の追加・編集・削除（メモ／タグ／カテゴリ／所属マップ／座標）
- 1場所を複数マップへ関連付け（複製せず重複統合）
- マップ長押しでの自由ピン追加、緯度経度指定
- ピン詳細／訪問済み・訪問回数
- マップ内・横断の検索／絞り込み／並び替え
- 受信箱（削除・再試行・キャンセル）と解析ジョブ状態
- 端末内日本語OCRと投稿文からの住所優先・複数候補抽出
- 1投稿から複数スポット選択、住所不一致確認
- 外部地図アプリでの経路案内（Google Maps / Apple Maps）
- Android 共有 Intent のネイティブ受信
- iOS Share Extension ソースと App Group 受け口
- Supabase 用 SQL マイグレーション
- Places / Geocoding の実サービスと、将来のAI API接続インターフェース

## SNS共有受信（Android / iOS）

共有は両OSとも同じ Flutter 経路に合流します。

```
OS共有
  → Android Intent / iOS Share Extension
  → MethodChannel `com.pinlogy/share`
  → ShareIntakeCoordinator
  → 受信箱へ即保存（解析はバックグラウンド）
  → 「受信箱に保存しました」
```

- **Android**: `MainActivity` で `SEND` / `SEND_MULTIPLE` を処理済み。実機で他アプリから共有して確認できます。
- **iOS**: App Group / URL Scheme / Extension ソースは用意済み。Xcode で Share Extension ターゲット追加が必要です（`ios/ShareExtension/README.md`）。

## 実行

```sh
flutter pub get
flutter run
```

## 検証

```sh
flutter analyze
flutter test
```

## 構成

```
lib/
  app/           # 起動、テーマ適用、状態管理
  core/          # テーマ、ID、エラー変換
  models/        # ドメインモデル
  repositories/  # Repository とローカル永続化
  services/      # 解析・検索・共有・経路・Backend設定
  features/      # maps / inbox / extraction / saved / places
  widgets/       # 共通UI
supabase/migrations/
ios/ShareExtension/
```

## バックエンド接続（未設定でも起動可）

1. `.env.example` を参考にサーバー側へキーを設定
2. `supabase/migrations/001_initial.sql` を適用
3. Edge Functions で解析・Geocoding・Places を実装
4. 必要に応じて端末内解析を専用AI APIクライアントへ差し替え

## ストア提出前の必須設定

- Android: `android/key.properties.example` をコピーして正式なUpload Keyを設定
- iOS: XcodeでTeam、Bundle ID、RunnerとShare ExtensionのApp Groupを設定
- Android SDK Platform 36をSDK Managerからインストール
- `ROUTING_API_BASE_URL` に本番のHTTPS経路APIを設定（未設定時は外部ナビ）
- プライバシーポリシーに、位置情報、住所検索、地図タイル、端末内OCRを記載
- Instagram / TikTok / 写真共有をAndroid・iOS実機で最終確認

**秘密APIキーは Flutter アプリに直接入れないでください。**

地図表示用キーは Android 署名・アプリID、iOS Bundle ID で制限してください。

## 場所抽出の設計

1. 共有されたURL・投稿文・画像を受信箱へ即時保存
2. OCRとマルチモーダル解析で店名・住所・地域を抽出
3. 投稿に明記された住所を最優先にジオコーディング
4. 住所周辺の地図データと店名・支店名を照合
5. 高信頼候補は選択済み、矛盾のある候補だけ確認
6. 選んだ複数スポットを任意のマップへ一括登録
