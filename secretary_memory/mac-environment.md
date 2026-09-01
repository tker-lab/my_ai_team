---
name: mac-environment
description: CEOのMacBook環境。ユーザー名はtakahashitakayuki、AIチーム拠点は~/my_ai_team
metadata: 
  node_type: memory
  type: project
  originSessionId: 8af4cad0-9329-478d-af66-cc59a14297ac
  modified: 2026-09-01T00:48:38.826Z
---

CEOは2026年9月にMacBookを導入し、Windowsと併用している。Mac側のユーザー名は `takahashitakayuki`。

- AIチーム拠点: `/Users/takahashitakayuki/my_ai_team`（Windowsは `C:\Users\PC_User\my_ai_team`）
- 秘書メモリ・会話ログ: `~/.claude/projects/-Users-takahashitakayuki-my-ai-team`（フォルダ名はプロジェクトのパスから生成されるため、Windows側の `c--Users-PC-User-my-ai-team` とは別名になる）

**Why:** ファイルパスを案内する際、どちらのマシンから話しているかで正解が変わるため。Mac側のパスは秘書がWindowsから見に行けない。

**How to apply:** パスを含む手順を案内する時は、まずどちらのマシンでの作業かを確認する。移行の経緯と手順は [[mac-migration-github-split]] を参照。
