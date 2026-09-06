---
name: storekit-testing-requires-xcode-run-not-cli
description: XcodeのStoreKitテスト(ローカル.storekit設定ファイル)は、xcodebuildをターミナルから単体実行しただけでは有効にならず、Xcode.app自体からRun/Testした場合のみ有効になる
metadata:
  type: project
---

PhotoTimerの課金機能(2026-09-06)で、`.storekit`設定ファイルをスキームに正しく紐付けても
(project.yml→xcodegen→.xcscheme内の`StoreKitConfigurationFileReference`まで確認済み)、
`xcodebuild test`/`xcodebuild build`をターミナルから直接実行した場合、実機ログ
(`log stream`でstorekitdを追跡)を見ると**本物のMedia API(Sandbox)へネットワーク越しに
問い合わせに行ってしまい、ローカル設定ファイルの内容が一切使われていない**ことを確認した。
これはこのアプリの実装不備ではなく、AppleのStoreKit Testing機能自体の仕様
(ローカル設定ファイルの割り込みはXcode.appのIDEプロセスがローンチ時に確立する接続に
依存しており、`xcodebuild`をターミナル単体で叩いただけでは有効にならない)による。

**How to apply:** StoreKit課金機能を実装した後、CLIでの自動テストで「商品情報を取得できません
でした」のようなエラー分岐に入るのは、コードの不具合ではなくこの制約が原因である可能性が高い。
実際に商品情報が正しく出るかは、**Xcode.appを開いてPlay(▶)ボタンでRunした場合**のみ確認できる。
CEOへの報告では、シミュレータ・実機どちらであっても「Xcodeで直接開いてRunする」手順を
明記すること。CIやターミナルだけでの完全自動検証は現状のAppleの制約上できない
(ロック→エラー表示→復元ボタン等、購入まわりのUI分岐そのものはCLIのUIテストでも確認可能)。
