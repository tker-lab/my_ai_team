---
name: xcuitest-accessibility-id-content-change-detection
description: GUI操作不可の実行環境でも、XCUITestとアクセシビリティIDを使えば「画面内容が実際に切り替わったか」を自動確認できる
metadata:
  type: project
---

## 何ができたか
この実行環境(Claude Code / サブエージェント)はシミュレータの画面を人手でタップできないが、XCUITest(XcodeのUI自動操作テスト)なら
アプリの起動・タップ・スクリーンショット取得・要素の状態確認をコードで実行できる。写真スライドショーアプリ(PhotoTimer)の
「タイマーが動きながら写真が実際に流れる」ことの自動確認(2026-09-04)で使った手法:

1. 表示中の写真/動画に、その素材のID(PHAssetのlocalIdentifier)を含む`accessibilityIdentifier`を付与する
   (例: `"media-photo-\(asset.localIdentifier)"`)。画面表示や動作には一切影響しない。
2. XCUITestから一定間隔でその要素の`.identifier`を読み取り、値が変化していれば「実際に切り替わった」と判定できる
   (スクリーンショットの画像比較より確実で軽量)。
3. 同時にスクリーンショット(`XCUIScreen.main.screenshot().pngRepresentation`)をファイルに直接書き出せば、
   人間(CEO)が後から目視確認できる証跡も残せる。

## 注意点(ハマった点)
- `PHAsset.localIdentifier`は`"UUID/L0/001"`のように`/`を含む。これをそのままファイル名に使うと
  パス区切りと誤認されて書き込みが失敗する(`try?`で握りつぶすと気づかない)。ファイル名に使う前に`/`を置換すること。
- xcodegenでUITestターゲットを追加する場合、`type: bundle.ui-testing` + `dependencies: [{target: 本体ターゲット}]` を
  project.ymlに書き、`schemes:`でtestアクションに紐付ければ`xcodebuild test`が通る(PhotoTimerで実績あり)。
- テストは`build-for-testing`→`test-without-building`の2段階に分けると、ビルドとテスト実行のログを分離できて原因切り分けがしやすい。
- `xcodebuild test -only-testing:<Target>/<Class>/<method>` で1つのテストだけ再実行できる(修正の確認が速い)。

## How to apply
今後どのアプリでも「実際に動いているか」をCEOの手を借りずに確認したい場面(GUI操作が必要な確認全般)でこの手法を使う。
特にライフサポート部等、他部署が同様にiPhoneアプリ寄りの確認作業を必要とする場合にも応用できる可能性がある。

## 追記(2026-09-04): 候補が少ないと「切り替わった」がidだけでは分からないことがある

テスト用ライブラリの動画が1本しかないケースで、動画の表示時間(何秒で次に切り替わるか)を計測しようとしたところ、
`localIdentifier`だけを目印にしていると**同じ動画が連続で選ばれた時に「表示され直した」ことを検出できず、
複数回分の再生時間をまとめて1回分と誤測定してしまった**(3秒で切り上げる設定のはずが11秒と計測される、等)。

**対策:** アプリ側の状態(TimerController)に「表示するたびに+1される通し番号」を持たせ、
アクセシビリティIDに `"media-video-\(通し番号)-\(localIdentifier)"` のように埋め込む。テスト側は
「要素が存在するか」だけでなく「identifier文字列が完全一致しているか」まで見ることで、同じ素材の
連続再生でも1回ごとの表示時間を正しく切り分けられる。

**How to apply:** 候補(テスト用データ)が少ない状態で「切り替わりの間隔・継続時間」を計測する時は、
localIdentifierのようなデータ由来の値だけに頼らず、アプリ側に軽量な通し番号を持たせて識別子に含める
ことを検討する。写真枚数が十分に多いテストデータなら発生しない問題だが、テスト環境で最小限のサンプル
データしか用意していない場合に特に起きやすい。

## 関連
[[photos-fetchoptions-predicate-crash]] — この手法で見つかった不具合
[[simulator-photos-permission-limitation]] — 同じ検証作業の前段(写真アクセス許可。2026-09-04にXCUITestからの自動突破に成功)
