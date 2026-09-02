---
name: notion-views-api-update
description: Notion APIでビュー(ボード/ギャラリー等)を自動作成できるかどうかの最新状況(確認済み)
metadata:
  type: project
---

【2026-09-02 確認済み】Notion APIでボードビュー・ギャラリービューを含む主要なビューは自動作成できる。API バージョン `2025-09-03` 以降が必須。一次情報(developers.notion.com/guides/data-apis/working-with-views)をWebFetchで再確認し、実際にMCPの `notion-create-view` でボードビュー(GROUP BY指定)とリストビュー(カテゴリでグループ化)を作成、正常に機能することを実データで検証済み(notion_idea_dbプロジェクトのYouTubeネタ帳DB)。「ギャラリービューは400エラーになる」という二次情報の懸念は今回のボード/リスト作成では再現せず。

**Why:** notion_idea_dbプロジェクトのフェーズ2着手前に一次情報と実機能検証が必要だったため([[notion-mcp-connection-approach]] 参照)。

**How to apply:** 今後Notionのビュー自動作成が必要な場面では、`notion-create-view`(DSLで `GROUP BY "プロパティ名"` 等を指定)を使ってよい。ただし以下2点は未解決のためAPI非対応として扱う。
1. **ビュータブの並び替え・デフォルトビュー指定はAPI非公開。** どのビューを最初に開かせるかはCEOに「タブをドラッグして並び替え」という1回の手動操作を依頼する必要がある。
2. **ボードビューの `hideEmptyGroups`(空のステータス列を隠す設定)はDSLで制御不可。** 初期状態でtrueになるため、データが入っていないステータス列は表示されないことがある。気になる場合はCEOがビューの「•••」メニューから手動でトグルを切り替える(1タップ)。
