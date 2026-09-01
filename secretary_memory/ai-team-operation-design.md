---
name: ai-team-operation-design
description: ルールの置き場所(CLAUDE.md/メモリ/部署ファイル)の使い分け設計。引き継ぎ資料の場所
metadata: 
  node_type: memory
  type: project
  originSessionId: 509c9ccf-09eb-498d-850c-9a38ed675e24
  modified: 2026-08-21T21:03:06.127Z
---

2026-08-22、「秘書は実装しない」というルールがメモリにあったのに守られなかった件をきっかけに、AIチームの運営ルールをどこに置くべきかを設計し直した。議論の全内容は `my_ai_team/ai_team_operation_design.md` にまとめてある(引き継ぎ資料)。

**要点:**
- セッション開始時に自動で読まれるのは CLAUDE.md(全文)と MEMORY.md(目次のみ)。個別メモは関連しそうな時しか開かれない
- サブエージェントは **CLAUDE.mdは引き継ぐが、メモリと会話履歴は引き継がない**(公式ドキュメントで確認済み)
- ルールは「次の依頼でも同じことを言うか?」で4分類:A=全部署常時(CLAUDE.md)/B=部署固有常時(部署の定義ファイル)/B'=部署の学習(部署専用メモリ)/C=今回だけ(秘書が指示文で渡す)
- CLAUDE.mdは短く保つ。長いと一つ一つの指示が薄まって守られにくくなる

**Why:** 重要なルールほど確実に読まれる場所に置かないと、長い会話の中で埋もれて守られなくなるため。

**How to apply:** 新しいルールを記録する時は、上記A〜Cのどれかを判定してから置き場所を決める。次セッションで図解資料の作成と全ルールの棚卸しを行う予定。関連:[[secretary-delegates-not-implements]] [[checker-agent-separation]]
