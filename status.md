# 現在の優先順位・ステータス

> 秘書が随時更新するステータスメモです。新しいセッション開始時は、ここを見て「今何にフォーカスしているか」を把握してください。

## 運用方針
- **全作業をMacBook 1台に集約する(2026-09-01に方針決定)。** Windows機は過去の動画アーカイブ(14.6GB)の置き場=書庫としてのみ残し、日常作業では開かない
- USDAの実データ(csv等7.1GB)はMacに運ばない。コードと引き継ぎ資料(12.5MB)だけ運び、必要になったらMac側でスクリプトを再実行して取り直す(フル再取得は4.5〜5時間)
- ライフサポート部の `life_team.md` はGit非同期のためMacには来ない。Windows版は引き継がず、Mac側でCEOにヒアリングして作り直す
- **CEOとのやり取りの基本窓口はClaude Codeとする(2026-09-01に方針決定)。** Copilotは基本窓口としては使わない
- **使用制限に当たった時の代替窓口としてCodexを併用する(2026-09-03に方針決定)。** 5部署とも移植済み。機密2部署(顧問・ライフサポート)も対象に含めるとCEOが判断。前提として学習利用の設定を3箇所オフ済み → 詳細は [knowledge_research.md](knowledge_research.md)

## 現在のフォーカス(2026-09-02時点)
- **メイン**:動画部(1本目を完成させる段階)
- **一時停止**:顧問(海外畜産統計の自動取得基盤づくり。9ソース実装済み)。**新しいソース(サイト)から取得する必要が出た時に再開する**(2026-09-01にCEO判断) → 詳細は [advisory_usda_project.md](advisory_usda_project.md)
- **サブ・ぼちぼち相談**:ライフサポート部(都度カジュアルに相談に乗る程度)
- **完了**:MacBookへの環境移行(2026-09-01完了)。手順書は [mac_migration.md](mac_migration.md)
- **稼働中**:アプリ開発部(2026-09-02にYouTubeネタ帳のNotion構築が完了) → 詳細は [app_team_notion_idea_db.md](app_team_notion_idea_db.md)
- **Codexが担当中**:PhotoTimer(メモリータイマー)の**App Store公開までの作業一式**(ストア素材・プライバシーポリシー等)。**2026-09-08時点でCEOがCodex側で進行中のため、この窓口からアプリ開発部を起動しないこと。** PhotoTimer関連の見覚えのないコミットはCodex由来 → 詳細は [app_team_photo_timer.md](app_team_photo_timer.md)
- **審査待ち**:Country Cards Collection(旧称:国カードバトル仮称)。**2026-09-18、App Reviewへ提出完了(ステータス「1.0 審査待ち」、最大48時間)。** REST Countries公式データへの切り替え(1,923枚フル収録)・広告SDK(AdMob)・アイコン確定(Codex)・ストア掲載文言/スクリーンショット/プライバシー申告・Releaseビルドのアップロードまで全て完了。詳細は[app_team_country_cards.md](app_team_country_cards.md)・[app_team_country_cards_store_listing.md](app_team_country_cards_store_listing.md)。審査結果(承認/却下)を待つのみ。承認されれば自動リリース設定のため即座に公開される
- **一時停止**:広報部(発信するアウトプットが揃ってから本格稼働)
- **将来構想・未着手**:コミュニケーション基盤(Discord構想) → 詳細は [communication_plan.md](communication_plan.md)
- **将来構想・仕様待ち**:運営状態ダッシュボード(ルール・部署定義・メモリをPC/スマホから確認できるアプリかサイト) → 経緯は [ai_team_operation_design.md](ai_team_operation_design.md) の9章

## 次にやること候補
- アプリ開発部:**PhotoTimerの公開作業はCodex側で進行中(上記参照)。この窓口では動かさない。** 公開が終わった段階で、次のアプリに移るかどうかをCEOに確認する
- 動画部:**CEOが子育て・研修で多忙のため、再開はCEOの手が空いてから(2026-09-15)。** v5の実物確認は完了(13分・字幕の全編チェック等が残り)。字幕の自動化の仕組み(案1)は2026-09-16に構築・試運転済み(手順書は youtube_team_subtitle_workflow.md)。再開時は1本目の仕上げから。未決:カット候補の自動リストアップは案のみ。詳細は [youtube_team_video1.md](youtube_team_video1.md)・[youtube_team.md](youtube_team.md)
- 顧問:(停止中。再開時は)UN Comtradeの2014年以降の再取得、MLA再取得の完了確認。Macにデータ本体が無いためフル再取得4.5〜5時間が必要

## 運営基盤の整備状況(2026-08-22時点)
- 5部署のサブエージェント定義ファイル(`.claude/agents/`)を新設済み。モデルは秘書=Opus / 部署=Sonnetで固定
- チェック担当を動画部・顧問部・アプリ開発部・広報部に導入済み(ライフサポート部は対象外)
- 部署専用メモリ(`memory: project`)を全5部署に設定済み
- 現在の全体像は「ルール台帳」(引き継ぎ資料)にまとめてある
