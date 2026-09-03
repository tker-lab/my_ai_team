---
name: xcode-setup-mac
description: MacBookでiPhoneアプリ開発環境を整える手順と、この実行環境(Claude Code)ではsudoが使えない制約
metadata:
  type: project
---

## sudoが必要な手順はCEOに手動実行してもらう
このセッション(Claude Code / サブエージェント)は非対話環境で動いており、`sudo` はパスワード入力ができず必ず失敗する(`sudo -n true` で確認済み、2026-09-03)。Xcodeの初期セットアップは以下がすべて sudo 必須:
- `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
- `sudo xcodebuild -license accept`
- `sudo xcodebuild -runFirstLaunch`

**Why:** rootのみ書き込める `/Library/Developer` や `/Applications/Xcode.app` 配下を変更するため。
**How to apply:** 同様のセットアップ・システム変更依頼が来たら、まず `sudo -n true` で非対話sudoの可否を確認し、無理なら早期に「CEOがターミナルに貼るだけのコマンド」を順序立てて提示する方針に切り替える。[[secretary-delegates-not-implements]] とは別軸の制約(部署がやっても物理的に無理)なので混同しない。

## Xcode直接ダウンロード版(.xip)はiOSシミュレータランタイムを同梱しない
2026-09-03時点、Xcode 26.6を`/Applications/Xcode.app`に直接インストールした状態(App Store経由ではない)では `Contents/Developer/Platforms/iPhoneSimulator.platform` 配下に `.simruntime` が見つからず、Xcode.app全体のサイズも3.5GBのみ(ランタイム同梱ありなら7〜12GB程度が目安)。
**Why:** ランタイムは別ダウンロード(`xcodebuild -downloadPlatform iOS`、数GB規模)が必要という前提でセットアップ手順・ETAを組む必要がある。
**How to apply:** 新しいMacでXcodeをセットアップする際は `xcrun simctl list runtimes` で確認し、無ければ `xcodebuild -downloadPlatform iOS` を案内する。ダウンロードは回線次第で15〜40分程度見ておく。

## .xcodeprojはXcodeを開かずxcodegenで作れる
`brew install xcodegen`(sudo不要)を使うと、`project.yml` というテキスト設定から `.xcodeproj` を生成でき、
Xcode GUIを一切開かずに新規iOSアプリの雛形を作れる。Info.plistもYAMLの `info.properties` から自動生成可能。
**Why:** このセッションにはGUI操作ができないため、Xcodeの「New Project」ウィザードは使えない。
**How to apply:** 新しいiOSアプリを作る時は毎回 `apps/<アプリ名>/project.yml` を書いて `xcodegen generate` する。
`.xcodeproj`自体はxcodegenでいつでも再生成できるので `.gitignore` に入れ、`project.yml`だけをコミット対象にする。

## 他部署への横展開ポイント
「このClaude Code実行環境ではsudoの対話入力ができない」という制約は、アプリ開発部に限らずシステム設定変更を伴うあらゆる部署の作業に共通する。秘書がknowledge.mdへの反映要否を判断する際の材料として報告済み。
