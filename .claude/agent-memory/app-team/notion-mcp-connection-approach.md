---
name: notion-mcp-connection-approach
description: NotionをMCP経由でClaude Codeから読み書きする際の推奨方式と、ページ単位でスコープを絞る理由
metadata:
  type: project
---

Notion公式MCPは2026年時点で「リモート版(ホスト型)」が推奨。接続は `claude mcp add --transport http notion https://mcp.notion.com/mcp` を実行後、Claude Code内で `/mcp` を叩いてOAuth認証する方式。ブラウザでNotionにログインし、OAuth同意画面で**どのページ・データベースを共有するか個別に選択**できる(ワークスペース全体を渡す必要はない)。この方式ではCEO側がアクセストークンを手動発行・入力する必要が一切ない(ローカル版のみ `NOTION_TOKEN` を設定ファイルに書く旧方式が必要)。

**Why:** 「アプリ開発部プロジェクト:notion_idea_db」で、CEOのYouTubeネタ帳をNotion化するにあたり、秘書(Claude Code)から読み書きできるようにする必要が生じた。CEOはNotion初心者かつアクセストークンをチャットに貼りたくない前提だったため、まず旧来の内部インテグレーション(NOTION_TOKEN)方式を想定していたが、公式ドキュメントを確認した結果リモートOAuth方式の方が安全かつ簡単だと判明(2026-08-27時点)。またCEOチーム運営上、顧問部(本業)・ライフサポート部(家族のプライベート)は機密分離の設計になっているため、Notionワークスペース全体ではなく**用途ごとの親ページ1つだけ**に接続許可を絞る運用にした。

**How to apply:** 今後どの部署であってもNotionをMCP接続する依頼が来たら、まずこのリモートOAuth方式(トークン不要・ページ単位スコープ)を提案する。旧ローカル版(`@notionhq/notion-mcp-server` + `NOTION_TOKEN`)は選ぶ理由がない限り勧めない。関連:[[notion-official-docs]]
