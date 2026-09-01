---
name: notion-official-docs
description: Notion関連(MCP接続・API・iPhoneアプリ操作)を調べる際に確認すべき公式ドキュメントの場所
metadata:
  type: reference
---

Notion関連の作業をする際は必ず以下の公式ソースを確認する(Notionは仕様変更が速いため記憶で書かない)。

- MCP接続の始め方:https://developers.notion.com/guides/mcp/get-started-with-mcp
- MCP概要:https://developers.notion.com/guides/mcp/overview
- 公式MCPサーバーのGitHub(ローカル版含む):https://github.com/makenotion/notion-mcp-server
- データベース作成:https://www.notion.com/help/create-a-database
- ビュー/フィルター/並び替え:https://www.notion.com/help/views-filters-and-sorts
- モバイル(iPhone/Android)ウィジェット:https://www.notion.com/help/mobile-widgets
- Views API(プログラムからのビュー作成、2025-09-03以降のAPIバージョンが必要):https://developers.notion.com/guides/data-apis/working-with-views

**Why:** 「notion_idea_db」プロジェクトでMCP連携手順を書く際、検索結果の二次情報だけでは古い/不正確な情報(例:ビューはAPIで作れないという通説)が混ざっていたため、一次情報URLを控えておく必要があった。[[notion-mcp-connection-approach]] [[notion-views-api-update]]

**How to apply:** Notionに関する手順書・設計メモを書く前に、このリストのURLを起点にWebFetchで最新状態を確認してから書く。
