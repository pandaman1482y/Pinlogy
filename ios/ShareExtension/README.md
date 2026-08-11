# Pinlogy iOS Share Extension

SNS（Instagram / TikTok など）から共有された URL・テキスト・画像を受け取り、
App Group 経由で本体アプリの受信箱へ渡します。

## 実装済みファイル

- `ShareViewController.swift` … 共有内容の収集・App Groupへの確実な保存
- `Info.plist` … テキスト / URL / 画像 / 動画の受け取り設定
- `ShareExtension.entitlements` … App Group `group.com.pinlogy.shared`
- `Base.lproj/MainInterface.storyboard`
- 本体側: `Runner/AppDelegate.swift` / `Runner/Runner.entitlements` / URL Scheme `pinlogy://`

## Xcode でターゲットを追加する手順

ソースは用意済みですが、**Share Extension ターゲット自体は Xcode 上での追加が必要**です。

1. `ios/Runner.xcworkspace` を開く
2. File > New > Target > Share Extension
3. Product Name: `ShareExtension`
4. Bundle Identifier 例: `com.pinlogy.pinlogy.ShareExtension`
5. 生成されたスケルトンを、このフォルダのファイルで置き換え（または参照を差し替え）
6. Signing & Capabilities で両ターゲットに App Groups を追加  
   - `group.com.pinlogy.shared`
7. Runner / ShareExtension 両方で同じ Team を選択
8. 実機またはシミュレータでビルド

## 受信フロー

```
他アプリの共有シート
  → ShareExtension（このターゲット）
  → 「Pinlogyに保存」をタップ
  → App Group UserDefaults の永続キューに JSON 保存
  → Pinlogy本体の起動を試行（iOSが許可しない場合は共有元へ戻る）
  → 自動で開かなかった場合は利用者がPinlogy本体を開く
  → AppDelegate が MethodChannel `com.pinlogy/share` へ渡す
  → Flutter ShareIntakeCoordinator が受信箱へ即保存
  → 「受信箱に保存しました」を表示
```

## 注意

- Apple Developer アカウントと App Group 能力が必要です
- iOSのShare Extensionは本体アプリの自動起動を保証しません。失敗しても最大50件の共有キューに残り、次回起動時にまとめて取り込みます
- ここまでのコードに有料APIキーは不要です
- 解析は本体アプリ側でバックグラウンド実行します
