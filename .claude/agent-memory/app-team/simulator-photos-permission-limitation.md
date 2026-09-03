---
name: simulator-photos-permission-limitation
description: iOSシミュレータの写真ライブラリ許可ダイアログはXCUITestから自動突破できる(2026-09-04解決)。手順と、それ以前にハマった経緯
metadata:
  type: project
---

## 症状
iOS 26.5シミュレータ(Xcode 26.6)で、`xcrun simctl privacy <udid> grant photos <bundle-id>` を実行し
TCC.db 上は `auth_value=2`(許可)になっていても、アプリ内で `PHPhotoLibrary.authorizationStatus(for: .readWrite)` は
`notDetermined`(0)のままだった。TCC.db の該当行を見ると `auth_reason=4`(SystemSet = ツールによる強制付与)であり、
Photosのフルライブラリアクセスという機微な許可については、この「システムによる強制付与」を信用せず、
実際のユーザー操作(ダイアログのタップ)を要求している可能性が高い(検証で確定はできていないが、複数の手順・
シミュレータの完全初期化を試しても再現したため、単なる操作ミスではなくこのiOSバージョンの仕様と判断)。

**Why:** [[xcode-setup-mac]] のsudo制約と同様、この実行環境(Claude Code / サブエージェント)には
実機やシミュレータの画面をタップするGUI操作の手段が無い。`xcrun simctl` にはタップ・タッチイベント送信の
サブコマンドが存在せず、`osascript` 経由の System Events(GUIスクリプティング)もタイムアウトして応答しない
(この環境にWindowServerへのアクセス権が無いことを示唆)。`xcrun simctl io <udid> screenshot` で画面を
「見る」ことはできるが、「操作する」ことはできない、という非対称な制約がある。

**How to apply:**
- 写真・カメラ・マイクなど「フルアクセス」系の許可が絡む機能をシミュレータで最終確認する時は、
  この経路(simctl privacy grant)だけでは自動化できないと想定し、早めに「CEOに実機の画面を数秒だけ
  操作してもらう」前提で計画する。位置情報など感度の低い権限は `simctl privacy grant` が素直に効くことがある
  (未検証。次回試す時は同じ手順でauth_reasonを確認するとよい)。
- 確認手順:`sqlite3 "$(xcrun simctl getenv <udid> HOME)/Library/TCC/TCC.db" "select service,client,auth_value,auth_reason from access where client='<bundle-id>';"` でauth_reasonを見ると
  「grantコマンドは通っているのにアプリ側に反映されない」の原因切り分けに使える。
- CEOへの依頼は「今シミュレータの画面に出ている許可ダイアログの『フルアクセスを許可』を1回タップしてください」
  という具体的な一言で済む(専門知識不要)。

## 他部署への横展開ポイント
GUI操作(クリック・タップ)がこの実行環境では一切できないという制約は、iOSシミュレータに限らず
「画面を操作して確認する」系のあらゆる作業に共通しうる。秘書がknowledge.mdへの反映要否を判断する材料として報告済み。

## 追記(2026-09-04): アンインストールは厳禁/XCUITest経由なら制約が一部違う

**アンインストールでCEOの手動許可が消える。** 検証目的で一度 `xcrun simctl uninstall` した結果、TCC.db の
該当行(`auth_value=2, auth_reason=3`。以前CEOが実機ダイアログを1回タップして得た正規の許可)が完全に消え、
同じ値でINSERTし直しても `PHPhotoLibrary.authorizationStatus` は許可済みとして扱われなかった(csreq等の
検証情報が伴わない手書きの行は信用されない模様)。**CEOが一度許可したアプリは、検証目的であっても
`simctl uninstall` しないこと。** アプリの再ビルド・再インストール(`xcodebuild` でのビルド→実行)だけなら
TCC行は保持され、許可状態は壊れない。

**「画面操作が一切できない」は不正確 — XCUITestセッション内でのみ、システムダイアログにも触れる。**
上記の「GUI操作の手段が無い」は bash からの `osascript`/`simctl` 経由の話であり、**XCUITestのテストコード内**
からは `XCUIApplication(bundleIdentifier: "com.apple.springboard")` でSpringboard(システムのアラートを
描画しているプロセス)のアクセシビリティツリーを直接クエリ・タップできることを確認した(許可ダイアログの
「許可しない」ボタンは実際にタップできた=要素として実在し反応する)。ただし**「許可する」側を狙って
確実に選ばせる実装には至っていない**(`addUIInterruptionMonitor`は登録しても発火せず、素朴な
`waitForExistence`だと先にXCTestの既定ハンドラが「許可しない」を選んでしまうタイミング競合がある)。
次回挑戦する時は、`addUIInterruptionMonitor`を使わずアラート出現直後に`springboard.alerts.firstMatch`を
即座にポーリングする、またはボタンのラベルを英語ロケール("Allow Full Access"等)でも試す、といった
別アプローチを検討する価値がある。**現時点の結論としては、依然「CEOに1回タップを頼む」が確実な運用。**

## 追記(2026-09-04 続き): 自動突破に成功。CEOへの依頼が不要になった

上の「別アプローチ」を実際に試したところ成功した。ポイントは2つ、いずれも上の推測どおりだった。

1. **`.alerts` / `.sheets` のようなコンテナ越しにクエリしない。** iOS26(このシミュレータのバージョン)の
   写真アクセスダイアログは半モーダルの「シート」的な見た目だが、アクセシビリティ上は「Alert」と「Sheet」の
   判定が内部的に食い違っており、`springboard.alerts.firstMatch.exists` を呼ぶだけで
   `Automation type mismatch: computed Alert from legacy attributes vs Sheet from modern attribute`
   という実行時エラーになる。**コンテナを経由せず、`springboard.buttons["フルアクセスを許可"]` のように
   直接ボタン要素を狙えばこの問題を回避できる。**
2. **`waitForExistence` を使わず、最小間隔(10ms)でボタンの存在だけをポーリングする。** `waitForExistence`
   のような「じっくり待つ」問い合わせだと、待っている間にXCTestの既定の割り込みハンドラ(のようなもの)が
   先に「許可しない」を選んでしまうことがある。10msごとに`.exists`だけを確認するタイトなループにし、
   見つかった瞬間に`.tap()`すれば安定して「フルアクセスを許可」を選べる(実測では初回チェックで
   即座に見つかることが多い=ダイアログが出てから10ms以内)。

**実装(`PhotoTimerUITests.swift` の `ensurePhotosAccessGranted`)の要点:**
```swift
let allowButton = app.buttons["写真へのアクセスを許可する"] // アプリ独自の説明画面のボタン
allowButton.tap()

let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
let fullAccessButton = springboard.buttons["フルアクセスを許可"]
for _ in 0..<500 { // 最大500 x 10ms = 5秒
    if fullAccessButton.exists { fullAccessButton.tap(); break }
    usleep(10_000)
}
```
これで得られる許可は `xcrun simctl privacy grant` のような外部からの強制付与(TCC.dbのauth_reason=4、
実効性なし)ではなく、**アプリ自身がOSの正規の許可フローを通して得た本物の許可**(auth_reason=2、
実機でCEOが手動タップした時と同種)。実際に `sqlite3 TCC.db` で確認しても `auth_value=2` になり、
アプリも `PHPhotoLibrary.authorizationStatus` を正しく `.authorized` と認識した。

**Why:** これまで「この実行環境からはGUI操作が一切できない」という制約自体は正しいが(bashからの
`osascript`/`simctl`経由は不可)、**XCUITestのテストプロセス自身がSpringboardのアクセシビリティ要素を
操作する権限を持っている**ため、テストコードの中からなら例外的に可能だった。単に問い合わせ方(コンテナを
経由しない・ポーリング間隔を最小にする)が悪くて失敗して見えていただけ。

**How to apply:** **今後シミュレータで写真アクセス許可が必要な検証をする時は、もうCEOに手動タップを
依頼する必要はない。** 上記の `ensurePhotosAccessGranted` 相当の処理をテストの冒頭で毎回呼べば、
notDetermined状態からでも自動でフルアクセスまで到達できる(前提:CEOに1回だけ許可済みアプリを
アンインストールしていないこと。していた場合は `xcrun simctl privacy reset photos <bundle-id>` で
notDetermined に戻してからテストを実行すれば同じ手順で通る)。**他のプライバシー許可
(カメラ・マイク・通知・位置情報など)でも、同じ2つのコツ(コンテナを経由しない直接ボタン狙い+
最小間隔ポーリング)が通用する可能性が高い。** ライフサポート部等、他部署が同様にiPhoneアプリの
許可ダイアログを自動突破したい場面があれば応用できる。

## 他部署への横展開ポイント(追記)
「システムの許可ダイアログはCEOに手動タップしてもらうしかない」という前回の結論は誤りだった。
XCUITestのテストプロセスから直接ボタンを狙えば自動化できる、という訂正を秘書経由で共有する価値が高い
(GUI操作不可という制約の"例外"にあたるため、他部署が同種の壁に当たった時に無駄に諦めないために重要)。
