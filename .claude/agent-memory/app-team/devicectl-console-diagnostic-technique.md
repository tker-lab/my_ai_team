---
name: devicectl-console-diagnostic-technique
description: 実機の事実確認をXcode GUI無しでCLIだけで行う方法。DEBUG+環境変数ゲートの一度きり診断+devicectl --consoleでのログ取得
metadata:
  type: project
---

CEOの実機(接続済みでも画面ロック中は`devicectl device process launch`が
`Unable to launch ... because the device was not, or could not be, unlocked`で失敗する。CEOにロック解除を
依頼してから再実行すれば通る(このAI実行環境からロック解除はできない)。

実機の「事実」(例:本当に位置情報付きの写真が何枚あるか)をCEOの手を煩わせず・恒久的なUI変更もせずに
確認したい時のパターン:

1. `#if DEBUG` かつ `ProcessInfo.processInfo.environment["何かのキー"] == "1"` の二重ガードで診断コードを
   書く(通常のCEOの利用では絶対に動かない。リリースビルドにも含まれない)。
2. 結果は`NSLog`で出す(画面には出さない。個人データそのものではなく件数等の集計値のみに留める)。
3. ビルド→実機へ`xcrun devicectl device install app --device <UDID> <.appのパス>`(アプリを消さず上書きできる。
   CEOの許可状態・保存データは保持される)。
4. `xcrun devicectl device process launch --device <UDID> --console -e '{"キー":"1"}' --terminate-existing
   <bundle-id> > ログファイル 2>&1 &` をバックグラウンドで起動し、出力ファイルをポーリング(Monitorツール等)
   してNSLog行が出たら診断終了とみなし、プロセスを終了する。

PhotoTimerの「場所」調査(2026-09-04)で実際に使用: `authorizationStatus=3(フルアクセス許可済み)`
`total=6296` `withLocation=0` という実データを取得し、「実装の不具合」ではなく「CEOの写真に位置情報が
そもそも付いていない(カメラの位置情報設定オフの可能性)」と確定できた。

**How to apply:** 実機でしか確認できない「事実」(件数・状態等)が必要で、恒久的なデバッグUIを増やしたくない時、
他部署のiPhoneアプリ検証でも同じ手順が使える。[[simulator-photos-permission-limitation]]と対になる、
シミュレータでは再現しない/確認できない類の調査で使う手法。
