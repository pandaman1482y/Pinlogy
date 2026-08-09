# Pinlogy リリースチェックリスト

## Google Play

- [ ] `android/key.properties.example` を `android/key.properties` にコピー
- [ ] Upload Keyを作成し、JKSを安全な場所にもバックアップ
- [ ] `flutter build appbundle --release` で正式署名AABを生成
- [ ] Play Consoleでアプリ署名、ストア説明、スクリーンショットを登録
- [ ] 位置情報・写真・インターネット利用をデータセーフティへ申告
- [ ] 内部テストトラックでInstagram/TikTok/画像共有を実機確認

## App Store

- [ ] XcodeでDeveloper TeamとBundle IDを設定
- [ ] RunnerとShare Extensionに同一App Groupを追加
- [ ] Share ExtensionターゲットをRunnerへEmbed
- [ ] App Privacyで位置情報、ユーザーコンテンツ、診断情報を申告
- [ ] TestFlightで写真選択、共有Extension、OCRを実機確認

## 共通

- [ ] プライバシーポリシーと利用規約をHTTPSで公開
- [ ] 問い合わせ先メールアドレスを用意
- [ ] 本番の `ROUTING_API_BASE_URL` を設定、または外部ナビのみで公開
- [ ] SupabaseでAnonymous Sign-Insを有効化し、6本のmigrationを順番に適用
- [ ] `analyze-post` Edge Functionを配置し、`OPENAI_API_KEY`をSupabase Secretへ設定
- [ ] AI解析の同意ON/OFFとローカルフォールバックを実機確認
- [ ] 公開マップに個人メモ・元投稿・訪問履歴が含まれないことを確認
- [ ] 本番タイル事業者のURL・帰属表示・利用上限を設定
- [ ] iOS Runner / ShareExtensionの両ターゲットへ同じTeamを設定
- [ ] App Group `group.com.pinlogy.shared`を両ターゲットで有効化
- [ ] iPhone実機でテキスト・URL・単一画像・複数画像の共有受信を確認
- [ ] `flutter build ipa --release`後にXcode OrganizerでValidate
- [ ] Android実機でInstagram/TikTokの`content://`共有画像OCRを確認
- [ ] `SUPABASE_URL` とPublishable/Anon Keyをビルド設定へ追加
- [ ] 地図・住所検索・経路サービスの利用規約と帰属表示を最終確認
- [ ] 初期データ、誤認識、圏外、位置情報拒否、写真拒否を確認
- [ ] バージョン番号とビルド番号を更新

## 現在の公開範囲

- 画像OCRは端末内で処理し、画像を解析サーバーへ送信しない
- 住所からピンを置く場合だけ、初回同意後に住所文字列を検索サービスへ送信
- アプリ内経路は本番URL設定時のみ利用し、未設定時は外部ナビを利用
- 場所共有は店名・住所・地図リンクのみ。メモ・元投稿は共有しない
