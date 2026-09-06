---
name: codex-parallel-work-awareness
description: CEOはClaude CodeとCodexを同じリポジトリで並行運用する。見覚えのない成果物はCodex由来の可能性を疑う
metadata: 
  node_type: memory
  type: feedback
  originSessionId: bdc6f4a6-9d65-4b3e-9aab-feb33eeca37a
  modified: 2026-09-06T08:18:29.818Z
---

CEOはClaude Code(このセッション)とCodex(別ツール、CEOが自分で開いて直接指示する)を、同じ
`my_ai_team`リポジトリに対して並行運用することがある。[[ai-team-operation-design]]

**運用ルール:**
- CEOは「今からCodexにこの範囲を頼む」と、着手直後に一言伝えるようにする(2026-09-06、秘書からの
  依頼を受けてCEOが同意)。完璧な報告は不要で、範囲が分かれば十分。
- Codexがコミット・push済みの作業は、部署への作業依頼前に必ず`git log`/`git status`を確認する
  習慣で気づける(このリポジトリでは既に実践中)。
- 危ないのは「Codexがまだコミットしていない作業」と「私の部署が指示範囲外に手を広げた作業」が
  偶然重なるケース。**見覚えのない成果物・ファイル・ディレクトリが出てきたら、まずCodexが今
  何をやっているかCEOに確認する**(自分の部署の暴走と決めつけない)。

**実例(2026-09-06):** app-teamが依頼外で`marketing/`(ストア公開素材の下書き:検索キーワード・
サポートページ・プライバシーポリシー)を作成していた。秘書がスコープ外の作業として指摘しコミット
対象から外したところ、CEOから「それCodexと今やってる内容かも」と判明。ストア公開素材はCodex担当と
して部署ファイルに区分け記録し、app-team側の下書きは破棄する方針にした。
