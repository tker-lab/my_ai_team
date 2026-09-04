---
name: simctl-defaults-cfprefsd-caching
description: xcrun simctl spawn defaults read/write は cfprefsd のキャッシュにより実態と食い違って見えることがある。確実な検証方法。
metadata:
  type: project
---

`xcrun simctl spawn <UDID> defaults read/write <bundle-id> <key>` は、iOSシミュレータの設定値(UserDefaults)を外部から読み書きできる便利なコマンドだが、cfprefsd(設定値を管理する常駐プロセス)のキャッシュにより、以下の2パターンで実態と食い違って見えることがある(PhotoTimerの検証中に両方で実際に遭遇・原因特定済み)。

1. **既に一度でも起動したことがあるアプリに対して外部から `defaults write` しても、アプリ内の `UserDefaults.standard` がそれを拾わないことがある。** 書き込み自体は実際のplistファイルには正しく反映されている(`plutil -p` で確認できる)のに、アプリの実行時にはcfprefsdの古いキャッシュが優先されてしまう。
2. **アプリが内部で `UserDefaults.standard.removeObject(forKey:)` を呼んだ直後に、外部から `defaults read` で確認すると、まだ削除前の値が見えることがある。** これはアプリ側の削除が実際には正しく効いていて、かつすぐ後に `synchronize()` するかアプリを完全終了させればディスク上も正しく消えているのに、外部の `defaults read` コマンド側がcfprefsdの古いキャッシュを読んでしまうために起こる(実際に確認した`raw plist`は正しく削除されていた)。

**Why:** これを知らずに「defaults readで古い値/削除したはずの値が見える」ことだけを見ると、アプリのコードにバグがあると誤診断してしまう(実際に本セッションで2回、無駄な調査に時間を使った)。

**How to apply:**
- 外部から新しい値を注入して検証したい場合は、**アプリを一度アンインストール→再インストールしてから、初回起動前に `defaults write` する**のが最も確実(cfprefsdにその後のキャッシュを構築させる余地を与えない)。
- アプリ内部の書き込み・削除が本当にディスクへ反映されたかを確認したい場合は、`xcrun simctl spawn <UDID> defaults read` に頼らず、**raw plistファイルを直接読む**: `<コンテナのdataパス>/Library/Preferences/<bundle-id>.plist` を `plutil -p <path>` で開く(コンテナのパスは `xcrun simctl get_app_container <UDID> <bundle-id> data` で取得できる)。
- この手法は他のiPhoneアプリ検証(離乳食管理アプリ・ライフプランシミュレーター等、UserDefaultsを使うあらゆるアプリ)でも同様に使える。

関連: [[simulator-photos-permission-limitation]](写真アクセス許可の自動突破)、[[xcode-setup-mac]]
