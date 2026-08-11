# Pinlogy iOS リリース手順

## 必要環境

- macOS と最新安定版Xcode
- Apple Developer Program
- Flutter stable / CocoaPods
- Bundle ID `com.pinlogy.pinlogy`
- Share Extension Bundle ID `com.pinlogy.pinlogy.ShareExtension`
- App Group `group.com.pinlogy.shared`

## 初回設定

1. `ios/Runner.xcworkspace` をXcodeで開く。
2. RunnerとShareExtensionの両ターゲットで同じTeamを選ぶ。
3. RunnerとShareExtensionのSigning & CapabilitiesにApp Groupsを追加し、`group.com.pinlogy.shared`を有効化する。
4. Apple Developerで両Bundle IDとApp GroupのProvisioning Profileが生成されていることを確認する。
5. `flutter pub get`、`cd ios && pod install`を実行する。

## 実機確認

- Instagram/TikTok/写真アプリの共有先に「Pinlogyに保存」が表示される。
- テキスト、URL、単一画像、複数画像が受信箱へ保存される。
- 画像内の日本語店名・住所をOCRできる。
- 位置情報を許可・拒否・設定で再許可した各状態を確認する。
- 共有直後にアプリが開かない場合でも、次回起動時に受信箱へ届くことを確認する。

## Archive

```sh
flutter clean
flutter pub get
cd ios
pod install --repo-update
cd ..
flutter build ipa --release \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY \
  --dart-define=ROUTING_API_BASE_URL=https://YOUR_ROUTING_ENDPOINT
```

生成したArchiveをXcode OrganizerでValidateし、App Store Connectへ送信する。

## App Store Connect

- 位置情報は「App使用中」のみを申告する。
- AI高度解析OFF時は投稿画像を端末内OCRだけで処理し、ON時は共有画像・動画サムネイルをSupabase経由でOpenAIへ送信する旨を記載する。
- 住所検索時は住所文字列を国土地理院/OpenStreetMapへ送る旨をプライバシーポリシーへ記載する。
- 暗号化輸出申告は`ITSAppUsesNonExemptEncryption = false`に合わせて回答する。
