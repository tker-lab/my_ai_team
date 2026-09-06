---
name: background-bash-run-in-background-double-detach
description: Bashツールで`run_in_background:true`にした上でコマンド末尾にも`&`を付けると、実プロセスがツールの追跡から外れて完了通知が来ない
metadata:
  type: project
---

**症状:** `command: "xcodebuild test ... > log 2>&1 &"` のように、コマンド自体の末尾にも`&`を
付けた状態で`run_in_background: true`を指定すると、Bashツールが「完了」と通知してくるのは
「バックグラウンドへの受け渡し(&)を実行したシェル」の終了であって、実際のxcodebuild
プロセスはさらにその先で完全に独立して動き続けている。ログファイルは書き込まれ続けるが、
ツールからは終了を検知できない(完了通知が実態より大幅に早く来る)。

**なぜ起きるか:** `run_in_background: true`は「このBash呼び出し自体」を非同期化する機能。
そこに自分でも`&`を付けると二重にバックグラウンド化してしまい、内側の`&`で生まれた子プロセスは
親シェル(=ツールが監視しているプロセス)からデタッチされる。

**対処:** どちらか一方だけを使う。
- `run_in_background: true`を使うなら、コマンド末尾に`&`を付けない(素の`xcodebuild test ...`)。
- 過去のコマンドとの整合や`disown`込みで手動管理したいなら、`run_in_background`を使わず
  普通のBash呼び出しで`... &`+`disown`し、`ps -p <PID>`でポーリングして完了を待つ
  (PhotoTimerのUIテスト実行で実際にこの手動ポーリング方式に切り替えて回避した)。
