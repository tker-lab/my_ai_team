---
name: subtitle-pipeline-setup
description: 字幕自動化パイプライン(whisper.cpp+WhisperX+BudouX)の構築内容・既知の限界・使い方(2026-09-15構築)
metadata:
  type: project
---

2026-09-15、字幕制作の自動化パイプラインを構築した。詳細な使い方は `~/my_ai_team/youtube_team_subtitle_workflow.md`、用語集は `~/my_ai_team/youtube_team_glossary.md`、スクリプト本体は `~/my_ai_team/tools/subtitle_pipeline/`(`transcribe_align.py` / `correct_and_wrap.py` / `glossary_lib.py`)。

**構成**:whisper.cpp(large-v3+VAD)で文字起こし → WhisperX(`jonatasgrosman/wav2vec2-large-xlsr-53-japanese`)で1文字ごとのタイムスタンプに補正 → 用語集(youtube_team_glossary.md)による誤字置換+うつのひらがな統一+フィラー削除 → BudouX(日本語分かち書き)で文節の塊を作り、2行以内・塊の途中で割らない形でSRT化。環境は `~/video_venv`(python3.12、`~/my_ai_team_venv`とは別)。

**技術的に分かったこと**:
- WhisperXは日本語で正常動作する(基本方針が事前に想定していた「断念してwhisper.cppの単語タイムスタンプで代替」は不要だった)。ただし稀に1セグメントだけアライメントに失敗する(`backtrack failed`。10分の音声中1回発生)。この場合`chars`が空になり、そのままだとタイムスタンプが0秒に落ちて字幕がずれるバグがあったため、`transcribe_align.py`側でセグメント区間に均等割りしたフォールバック時刻を補う実装にしてある(該当箇所はログに`WARNING: segment N had no char alignment`と出る)
- BudouXの塊分割は「という/ていただく/おります/指示語(この/その等)」のような機能語が単独の塊として孤立し、それをそのまま改行位置に使うと不自然な位置で割れる(例:「この/後紹介するんですけど」)。`correct_and_wrap.py`の`_merge_unsplittable()`で既知パターンを直前/直後の塊に強制結合する後処理を入れて対処したが、網羅的ではないため、初見の言い回しでは同種の不自然な改行が残り得る
- フィラー「まあ」は文中で句読点が直後に来ないことが多い(例:「まあそうやってですね」)。最初、句読点直前限定の正規表現にしていたら大量に取りこぼした→無条件マッチに修正した([[glossary_correction_notes]]参照、なければ今後作成)
- 通常のHomebrew `ffmpeg`formulaには字幕焼き込み(libass)が入っていない。焼き込みには別途`brew install ffmpeg-full`(keg-only、`/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg`)が必要
- Aegisubのbrew caskは2026-09-01付でGatekeeper非対応のため無効化されている(Apple公証未取得)。代替として署名・公証済みの`Subtitle Edit`(brew cask、Apple Silicon対応)を導入した

**未解決・CEO確認待ち**:
- CEOのチャンネル内ニックネームの正しい表記(「こたろー」か「こたろう」か)。ファイル名`kotaro_MASTER_v5.mp4`からの推測で用語集には「こたろー」と暫定登録しているが未確定

**試運転結果の概要**(詳細は秘書への完了報告参照):IMG_3156.MOV(302秒)・IMG_3163.MOV(609秒)の両方で通し実行に成功。旧scratch SRTとの比較で、機械的な等間隔区切り(旧:平均2.7秒・重なり7件)→新:平均2.6秒だが内容に応じて可変・重なり0件、うつのひらがな統一の徹底(旧に鬱の漢字残り1件確認→新は0件)、単語・文節途中の改行が解消、を確認済み。

関連:[[video1_v5_status]](1本目本編の編集状況)、[[audio_sfx_verification_technique]]
