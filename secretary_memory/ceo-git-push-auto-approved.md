---
name: ceo-git-push-auto-approved
description: git pushの自動実行を許可
metadata: 
  node_type: memory
  type: feedback
  modified: 2026-09-01T00:00:00.000Z
---

秘書が Git リポジトリに変更を加えた際の `git push` について、CEO から明確な自動実行許可を得た（2026-09-01）。

毎回の確認取得が運用効率を損なうため、以下のように実行する：

**秘書の自動実行フロー：**
1. 作業終了時に秘書が自動で `git status` を実行
2. 変更を確認してから `git add` → `git commit` → `git push` を自動実行
3. 結果をCEOに報告（ログ表示で事後報告）

**除外事項（絶対に確認を取る）：**
- Windows 側への変更・操作
- `~/my_ai_team` 外のファイル削除
- 秘書メモリの追記（新ルール追加など）

**重要：Git 操作前に `git status` の内容を常に確認し、予期しない変更がないかチェック。**
