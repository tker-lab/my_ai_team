---
name: notion-page-deletion-limitation
description: Notion MCPにはページ/データベース行を削除(ゴミ箱に移動)するツールが存在しない
metadata:
  type: reference
---

Notion公式MCP(リモート版)のツール一覧には、ページやデータベース行を削除・アーカイブするツールが無い(create-pages / update-page / move-pages / duplicate-page はあるが、delete/trash/archive系のツールは非公開)。そのためMCP経由で作成した動作確認用サンプルデータは、プログラムからは消せない。

**Why:** notion_idea_dbプロジェクトでネタ帳DBの動作確認用サンプルを3件作成後、削除しようとしたが該当ツールが見つからなかった(2026-09-02)。ToolSearchで「delete/trash/archive」系のキーワードで検索しても該当なし。

**How to apply:** Notion上でMCP経由の動作確認のためにテスト行・テストページを作る際は、①事前に「確認後は手動削除が必要」と申告する、②該当ページのタイトルに「🗑️削除してOK」等の分かりやすい目印を付けて選びやすくしておく、の2点をセットで行う。CEOへの依頼は「該当の行を選択してDeleteキー(またはiPhoneならスワイプ→削除)」程度の短い一言で済む。関連:[[notion-mcp-connection-approach]] [[notion-official-docs]]

**注意(2026-09-02追記):** `notion-update-data-source` には `in_trash` という引数があるが、これは**データベース(データソース)全体**をゴミ箱に移動するものであり、個別の行(サンプルページ)だけを消す手段ではない。紛らわしいので、行単位の削除が必要な場面でこれを使おうとしないこと。→ 上記の結論(行削除ツールなし)は変わらず。この教訓を踏まえ、notion_idea_dbフェーズ2(広報ネタ帳)では動作確認サンプルを作らず、スキーマとビュー設定の確認だけで済ませる運用に切り替えた。
