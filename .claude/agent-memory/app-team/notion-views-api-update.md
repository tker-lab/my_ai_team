---
name: notion-views-api-update
description: Notion APIでビュー(ボード/ギャラリー等)を自動作成できるかどうかの最新状況(要再確認フラグ付き)
metadata:
  type: project
---

「NotionのUI上のビュー(ボード/ギャラリー/一覧など)はAPIから自動作成できない」という通説は2026年時点で古くなっている可能性が高い。2025-09-03以降のAPIバージョンで「Views API」が追加され、公式ガイド(developers.notion.com/guides/data-apis/working-with-views)ではテーブル・ボード・ギャラリー等の作成やgroup_by/filter/sortsの設定がAPI経由で可能と説明されている。一方で二次情報(ブログ記事)では「ギャラリービューはAPIで400エラーになり2026年内に対応予定」という記述もあり、**情報源によって食い違いがある**。

**Why:** notion_idea_dbプロジェクトで、フェーズ2(Notion API経由でのデータベース自動構築)を計画する前提として「ビューは手作業必須」という線引きをCEO・秘書に伝えていたが、これが最新仕様と合っていない可能性が出てきた。ここで一次情報(公式ガイド)と二次情報(ブログ)が矛盾しているため、まだ「確実に自動化できる」と断定はしていない。

**How to apply:** フェーズ2でNotion API経由のデータベース/ビュー自動構築に着手する前に、必ず developers.notion.com の一次情報(APIリファレンスの実エンドポイント仕様、可能なら実際にAPI呼び出しをテスト)で再確認すること。ボードビューの自動作成は比較的信頼度が高いが、ギャラリービューは未確認のまま計画に織り込まない。関連:[[notion-official-docs]] [[notion-mcp-connection-approach]]
