---
name: artifact-update-on-request-only
description: 運営台帳などの図解付きArtifactは、タスク完了の都度再発行せず、要望があった時だけ更新する
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 54a63adc-2098-47ff-bd30-0eea59d7fd2e
  modified: 2026-08-21T21:34:41.585Z
---

CEOより(2026-08-22):図解付き資料(Artifact)は都度編集しなくてよい、との指示。

**Why:** モデル選定・CLAUDE.md確認のような小さな決定が確定するたびにArtifactを再発行するのは過剰。見た目のある成果物の更新は、確認・共有のタイミングでまとめて行えば十分。

**How to apply:** [[secretary-delegates-not-implements]] の運営台帳などArtifactは、CEOから明示的に「更新して」と言われた時、または内容がまとまった区切り(章の追加など)の時だけ再発行する。一方、テキストの記録(`ai_team_operation_design.md` などの通常のmdファイル)は、経緯を追える台帳として引き続き都度更新してよい — 止めてほしいのはArtifactの再発行の頻度であって、記録自体ではない。
