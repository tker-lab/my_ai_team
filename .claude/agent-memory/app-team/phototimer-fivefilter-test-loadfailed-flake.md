---
name: phototimer-fivefilter-test-loadfailed-flake
description: PhotoTimerのtestFiveFilterCombinationが、UI変更と無関係にloadFailed(iCloud等で読み込めない)状態を検知できず再現性よく失敗する
metadata:
  type: project
---

2026-09-06のUI・文言調整作業中に発見(未修正。次に触る人向けのメモ)。

**現象:** `testFiveFilterCombination`(PhotoTimerUITests.swift)が単独実行でも再現性よく
失敗する。エラーは「5フィルタを同時に指定してスタートしたら20秒経っても決着しなかった」。

**原因:** テストは「決着」を`noResultsText`(「条件に合う写真・動画が見つかりませんでした」)
か`mediaElement`の出現だけで判定しているが、実際の画面は`.loadFailed`理由の別テキスト
(「写真・動画を読み込めませんでした(iCloud上にしか無い〜)」)で止まっていた。
スクリーンショットで実際にiCloudマークのついたloadFailed画面を確認済み。

**UI変更との関係:** [[swiftui-picker-fontdesign-buttonstyle-notes]]で対応した
FilterOptionsViewのアルバムセクション移動がきっかけで顕在化した可能性はあるが、
テスト自体が`.loadFailed`を「決着」として認識しない作りだったことが直接の原因であり、
根本原因はテスト用ライブラリの一部アセットが実際に読み込めない環境状態にあると見られる。
UI文言修正のスコープ外と判断し、今回は手を付けていない(PROGRESS.log 2026-09-06参照)。

**次に触るときの入り口:** テストの`settledAs`判定に`.loadFailed`用の文言チェックを足すか、
そもそもなぜテスト用ライブラリの一部アセットが読み込めない状態になっているか
(シミュレータの写真ライブラリの状態、ストレージ最適化設定等)を先に調べる。
