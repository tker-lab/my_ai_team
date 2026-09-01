# 顧問部(USDA案件)Mac移行手順書

※この手順書はMacBook側で起動したClaude Code(あなた)が読み、作業を代行する前提で書かれています。
あなたは今日までの経緯を知りません。必要な背景はこのファイルと、この後あなたが配置する
`advisory.md`・`advisory_usda_project.md`(手順2)に書かれているので、そちらも読んでから作業してください。

**方針**: 顧問部(海外畜産統計の自動取得プロジェクト)の作業場所を、Windows機からこのMacへ移します。
CEOが「Macに入れて困る機密はない」と判断済みのため、これまでの「顧問部はWindows据え置き」方針は
変更されました(`mac_migration.md`の手順4・手順9にある「顧問部はWindows据え置き」という記述は
この移行により古くなっています。矛盾する場合はこの手順書を優先してください)。

**厳守事項(mac_migration.mdと同じルールです)**
- 上から順に実行し、各手順の完了を実際のコマンド出力で確認してから次に進んでください。
- `git push`は行わないこと(必ずCEOの確認を得てから)。
- 判断に迷ったら、勝手に進めず状況をCEOに報告してください。
- **実際のデータ(CSV等7.1GB)は今回運びません。** コードと引き継ぎ資料だけを移し、
  データが必要になったら手順7の方法でMac側から取り直します。したがって手順が終わった直後は
  出力用フォルダ(`output`から始まるフォルダ)が空、または存在しない状態です。**これは異常では
  ありません。**

## 前提

`mac_migration.md`の手順1〜11(Homebrew・Node.js・Claude Code本体・リポジトリのclone・
秘書メモリ・グローバル設定など)が完了していることが前提です。未完了ならこの手順書より先に
そちらを終わらせてください(完了しているかは`~/my_ai_team`が存在し`claude`が起動することで判断できます)。

---

## 1. LocalSendの準備(Mac側に未導入の場合)

LocalSendは、同じWi-Fiに繋がった2台の間でファイルをアプリ間で直接送るツールです(クラウドを
経由しないので社内規定に触れにくいという理由で採用しています)。Windows側には導入済みです。

Macにまだ入っていない場合:
```
brew install --cask localsend
```
うまくいかない場合は https://localsend.org/ からMac版をダウンロードしてインストールしてください。
インストール後、一度起動して「同じWi-Fi上の端末」としてWindows機から見えることを確認してください
(Windows側でCEOに送信操作をしてもらいます)。

---

## 2. `USDA_送信用`フォルダを受け取り、`~/Desktop/USDA_PSD_Data`として配置する

Windows側で、CEOが`USDA_送信用`フォルダ(コードと引き継ぎ資料のみ、約12.5MB)をLocalSendで
このMacへ送ります。CEOに送信操作をお願いし、Mac側で受信を承認してください。

LocalSendの受信ファイルは既定で`~/Downloads`(ダウンロードフォルダ)に保存されます。届いたら
以下を確認・実行してください。

```
ls ~/Downloads/
```
`USDA_送信用`という名前のフォルダが届いていることを確認したら、**デスクトップに移動しつつ
フォルダ名をWindows側と同じ`USDA_PSD_Data`に戻します**(スクリプト内のパス参照をWindows側と
揃えるためです。手順4でこの名前を前提にパスを置換します)。

```
mv ~/Downloads/USDA_送信用 ~/Desktop/USDA_PSD_Data
```

配置できたら、隠しファイル(名前が`.`で始まるファイル。Finderでは標準で表示されません)である
`.env`(APIキーが書かれた設定ファイル)が実際に届いているか、ターミナルで確認してください。

```
ls -la ~/Desktop/USDA_PSD_Data/.env
```
ファイルサイズが表示されればOKです。`No such file or directory`と出た場合は転送漏れなので、
CEOに再送を依頼してください(LocalSendはフォルダ転送に対応しているので通常は一緒に届きますが、
CEOが個別ファイルを手動選択して送っていた場合は`.env`が見えずに漏れる可能性があります)。

念のため、`.py`ファイルが95本届いているかも確認してください。

```
find ~/Desktop/USDA_PSD_Data -maxdepth 1 -name "*.py" | wc -l
```
`95`と表示されればOKです。

---

## 3. 顧問部の機密ファイル3件の配置

`advisory.md`・`advisory_usda_project.md`・`.claude/agent-memory/advisory-team/`(顧問部の
作業メモリ)の3つは、`.gitignore`で意図的にGit管理から除外されています(機密情報のため、
リポジトリのcloneでは来ません)。これらもLocalSendで別途CEOから送ってもらい、手動で配置します。

CEOに、Windows側の以下の3つをLocalSendで送るよう依頼してください。
- `advisory.md`(1ファイル)
- `advisory_usda_project.md`(1ファイル)
- `.claude\agent-memory\advisory-team\`フォルダ一式

届いたら、配置先のフォルダが無ければ先に作成します。

```
mkdir -p ~/my_ai_team/.claude/agent-memory/advisory-team
```

届いたファイルを正しい場所へ移動してください(`~/Downloads`に届いている前提です。実際の
届き先はターミナルで`ls ~/Downloads/`を見て確認してください)。

```
mv ~/Downloads/advisory.md ~/my_ai_team/advisory.md
mv ~/Downloads/advisory_usda_project.md ~/my_ai_team/advisory_usda_project.md
```

`.claude/agent-memory/advisory-team/`は、CEOがフォルダごと送ってきた場合は中身を`cp -r`で
まとめて移してください(フォルダ名は届き方によって変わるので`ls ~/Downloads/`で実際の名前を
確認してから実行すること)。

```
cp -r ~/Downloads/advisory-team/. ~/my_ai_team/.claude/agent-memory/advisory-team/
```

配置後、ファイル数を確認してください(この文書を書いた時点で20件前後のはずです)。

```
ls ~/my_ai_team/.claude/agent-memory/advisory-team/ | wc -l
```

---

## 4. Windows専用パスの置換

**今回の対象は12.5MBと小さく、実データ(数GB)は含まれていないため、バックアップを取っても
容量はごくわずかです。** 置換前に必ずバックアップを取ってから進めてください。

置換元(Windowsのバックスラッシュ区切り)→ 置換先(Macのスラッシュ区切り):
```
C:\Users\PC_User\Desktop\USDA_PSD_Data
    ↓
/Users/takahashitakayuki/Desktop/USDA_PSD_Data
```

### 4-1. 対象ファイルの実際の一覧(grepで確認済み)

このパスが書かれているのは以下の**17ファイル**です(2026-09-01時点、Windows側で実際にgrepして
確認済み)。Mac側でも念のため同じ内容か再確認してから進めてください。

**(A) 顧問部メモリ(手順3で配置した`.claude/agent-memory/advisory-team/`配下、14ファイル)**

| ファイル:行 |
|---|
| `project_brazil_format13col.md:9` |
| `project_mla_dedup_scope_narrowing.md:8` |
| `project_mla_translation_completion.md:8` |
| `project_mla_comtrade_report1_verification.md:12` |
| `project_mla_report4_country_agg.md:8` |
| `project_term_master_final_check.md:9` |
| `project_mla_headcount_r67_delete.md:8` |
| `project_mla_chunk_progress.md:8` |
| `project_run_all_psd_gap.md:8` |
| `project_psd_config_and_update_policy.md:8` |
| `project_psd_format2_conversion.md:8` |
| `project_freshness_timing_survey.md:10` |
| `project_mla_unit_matrix.md:10` |
| `project_frequency_column_addition.md:10` |

**(B) `USDA_PSD_Data`直下の.pyファイル(3ファイル)** ※こちらはドキュメントではなく実際に動く
コードで、パスが直っていないとスクリプトが正しく動かない(マスタファイルが見つからない等の
エラーになる)ため重要です。

| ファイル:行 | 内容 |
|---|---|
| `country_master.py:33` | `MASTER_FILE_PATH = Path(r"C:\Users\PC_User\Desktop\USDA_PSD_Data\原産国マスタ.xlsx")` |
| `build_freshness_report.py:13` | `BASE = Path(r"C:\Users\PC_User\Desktop\USDA_PSD_Data")` |
| `freshness_timing_analysis.py:20` | `BASE = Path(r"C:\Users\PC_User\Desktop\USDA_PSD_Data")` |

### 4-2. 事前確認(grep)

まず`grep`(ファイルの中から文字列を探すコマンド)で、想定通り17件あるか数えてください。
`--exclude-dir=.git`は「.gitフォルダの中は見ない」(Gitの内部管理ファイルは対象外にする)、
`-I`は「バイナリファイル(xlsxなど文字として読めないファイル)は無視する」という意味です。

```
grep -rn --exclude-dir=.git -I 'C:\\Users\\PC_User\\Desktop\\USDA_PSD_Data' ~/my_ai_team/.claude/agent-memory/advisory-team ~/Desktop/USDA_PSD_Data/country_master.py ~/Desktop/USDA_PSD_Data/build_freshness_report.py ~/Desktop/USDA_PSD_Data/freshness_timing_analysis.py
```
17行表示されれば上の一覧と一致しているはずです。件数が違う場合は、先に進まずCEOに報告してください。

次に、大文字・小文字の表記ゆれ(例:`c:\users\pc_user`のような小文字表記)が無いか、
小文字にして再検索します(`-i`は大文字小文字を区別しないオプション)。

```
grep -rni --exclude-dir=.git -I 'c:\\users\\pc_user' ~/my_ai_team/.claude/agent-memory/advisory-team ~/Desktop/USDA_PSD_Data
```
上の17件以外に何か出てきた場合は、その分も置換対象に追加してください(2026-09-01時点の調査では
追加の該当なしを確認済みです)。

### 4-3. バックアップ

```
cp -r ~/my_ai_team/.claude/agent-memory/advisory-team ~/my_ai_team/.claude/agent-memory/advisory-team_backup_20260901
cp ~/Desktop/USDA_PSD_Data/country_master.py ~/Desktop/USDA_PSD_Data/country_master.py.bak
cp ~/Desktop/USDA_PSD_Data/build_freshness_report.py ~/Desktop/USDA_PSD_Data/build_freshness_report.py.bak
cp ~/Desktop/USDA_PSD_Data/freshness_timing_analysis.py ~/Desktop/USDA_PSD_Data/freshness_timing_analysis.py.bak
```
(日付`20260901`は実行日に合わせて変えて構いません。)

### 4-4. 置換の実行

`sed`はファイルの中の文字列を書き換えるコマンドです。**macOSのsedは`-i`の直後に
空文字の引数`''`を書く必要があります**(Windows/Linuxの`sed -i`とはここだけ書き方が違うので
注意。`''`を忘れると「元のファイル名+拡張子」を要求されエラーになります)。

区切り文字は`/`ではなく`#`を使います(置換後の文字列に`/`が含まれるため、`/`のままだと
コマンドが崩れてしまうからです)。バックスラッシュ`\`は`sed`の中では`\\`と書くことで
「1個のバックスラッシュそのもの」を表せます。

以下をまとめて実行してください(対象17ファイルをループで処理します)。

```
for f in \
  ~/my_ai_team/.claude/agent-memory/advisory-team/project_brazil_format13col.md \
  ~/my_ai_team/.claude/agent-memory/advisory-team/project_mla_dedup_scope_narrowing.md \
  ~/my_ai_team/.claude/agent-memory/advisory-team/project_mla_translation_completion.md \
  ~/my_ai_team/.claude/agent-memory/advisory-team/project_mla_comtrade_report1_verification.md \
  ~/my_ai_team/.claude/agent-memory/advisory-team/project_mla_report4_country_agg.md \
  ~/my_ai_team/.claude/agent-memory/advisory-team/project_term_master_final_check.md \
  ~/my_ai_team/.claude/agent-memory/advisory-team/project_mla_headcount_r67_delete.md \
  ~/my_ai_team/.claude/agent-memory/advisory-team/project_mla_chunk_progress.md \
  ~/my_ai_team/.claude/agent-memory/advisory-team/project_run_all_psd_gap.md \
  ~/my_ai_team/.claude/agent-memory/advisory-team/project_psd_config_and_update_policy.md \
  ~/my_ai_team/.claude/agent-memory/advisory-team/project_psd_format2_conversion.md \
  ~/my_ai_team/.claude/agent-memory/advisory-team/project_freshness_timing_survey.md \
  ~/my_ai_team/.claude/agent-memory/advisory-team/project_mla_unit_matrix.md \
  ~/my_ai_team/.claude/agent-memory/advisory-team/project_frequency_column_addition.md \
  ~/Desktop/USDA_PSD_Data/country_master.py \
  ~/Desktop/USDA_PSD_Data/build_freshness_report.py \
  ~/Desktop/USDA_PSD_Data/freshness_timing_analysis.py \
; do
  sed -i '' 's#C:\\Users\\PC_User\\Desktop\\USDA_PSD_Data#/Users/takahashitakayuki/Desktop/USDA_PSD_Data#g' "$f"
done
```

### 4-5. 事後確認

もう一度4-2と同じgrepを実行し、**0件になっていること**を確認してください。

```
grep -rn --exclude-dir=.git -I 'C:\\Users\\PC_User' ~/my_ai_team/.claude/agent-memory/advisory-team ~/Desktop/USDA_PSD_Data
```
何も表示されなければ成功です。成功を確認できたら、4-3で作った`.bak`ファイルと
`advisory-team_backup_20260901`フォルダは削除して構いません(念のため数日残しておいても構いません)。

```
rm ~/Desktop/USDA_PSD_Data/*.bak
```

### 4-6. `設定.xlsx`の目視確認(手動)

`設定.xlsx`(保存先フォルダを指定する設定ファイル)は表計算ファイルのため`grep`で中身を
検索できません。Numbers等で開き、「保存先設定」シートにWindowsのパス(`C:\`から始まる文字列)が
書き込まれていないか目視で確認してください。空欄であれば何もしなくてよい設計です(空欄の場合は
各スクリプトが自動的にプロジェクトフォルダ内の既定フォルダを使うため)。もし何か書かれていた場合は、
同じ考え方でMacのパスに書き直すか、空欄に戻してください。

---

## 5. Python環境の構築

`mac_migration.md`の手順1-4がまだであれば、ここで実施します。

```
brew install python
python3 -m venv ~/my_ai_team_venv
source ~/my_ai_team_venv/bin/activate
```

顧問部のスクリプトが実際にimportしているライブラリを確認したところ(2026-09-01、全.pyファイルを
確認済み)、標準ライブラリ(pathlib、csv、json、re等、Pythonに最初から入っているもの)以外で
必要なのは以下の5つで、`requirements.txt`の内容と一致していました。追加は不要です。

```
pip install pandas openpyxl requests python-dotenv comtradeapicall
```
(`pip install -r ~/Desktop/USDA_PSD_Data/requirements.txt`でも同じ結果になります。)

**このターミナルを閉じると仮想環境から抜けます。** 次回以降スクリプトを動かす前には、必ず
`source ~/my_ai_team_venv/bin/activate`を実行してください。

---

## 6. 動作確認

まず、これから動かすのは**取得(fetch)側**のスクリプトであり、実データを転送していないため、
`output_*`という名前のフォルダが存在しない、または空であるのは正常な状態です(データを一度も
取得していないだけで、故障ではありません)。

軽くて短時間(数秒)・APIキー不要で終わる`fetch_brazil_ibge.py`(ブラジルの畜産統計取得)を
使って起動確認します。

```
cd ~/Desktop/USDA_PSD_Data
source ~/my_ai_team_venv/bin/activate
python fetch_brazil_ibge.py
```

正常に動くと、数秒で「取得: ◯◯行」のような表示が出て終了し、`output_brazil`フォルダが
新規作成されてCSVが1つできます。ここでエラーが出た場合は、手順4のパス置換漏れ(特に
`country_master.py`のようにimportされる側のファイル)や、手順5のライブラリ不足が疑われます。
エラー画面の内容を確認し、自己判断で無理に直そうとせず、内容をCEOに報告してください
(一般的なエラーはChatGPT等のAIチャットにエラー画面を貼って聞くと解決の糸口が見つかることが
多いですが、顧問部の作業内容自体は機密のため、社外のAIチャットには**エラーメッセージの文言のみ**
を貼り、ファイルの中身やデータそのものは貼らないよう注意してください)。

---

## 7. データを取り直す方法(必要になった時)

**`.bat`ファイル(1_全部実行.bat 等)はWindows専用の仕組みのため、Macでは実行できません。**
中身は結局`python run_all.py <引数>`を呼んでいるだけなので、Macでは直接そのコマンドを
ターミナルで実行してください(事前に`cd ~/Desktop/USDA_PSD_Data`と仮想環境の有効化が必要です)。

| Windows(.bat) | Mac(ターミナルで実行するコマンド) | 内容 | 所要時間の目安 |
|---|---|---|---|
| `1_全部実行.bat` | `python run_all.py all` | 全10ソースを最初から順番に全期間取得 | 約4.5〜5時間(直列実行。MLAはサーバーが不安定な時があり、その場合は半日近くかかることもある) |
| `2_UNコムトレードだけ.bat` | `python run_all.py comtrade` | UN Comtrade(貿易統計)のみ | 約100分。**1日あたりのAPI呼び出し上限があるため、日をまたいで様子を見ながら実行すること**(上限に達すると"Out of call volume quota"というエラーで、無言のままデータが一部欠落する) |
| `3_MLAとUSDAだけ.bat` | `python run_all.py heavy` | MLA(豪州)+USDA AMS(米国相場)。最も時間がかかる組み合わせ | AMSだけで約43分。MLAを含めると数時間〜(不安定な時は半日近く)、余裕を持って半日を見込む |
| `4_その他の国だけ.bat` | `python run_all.py others` | USDA PSD+ブラジル+カナダ+EU+チリ+メキシコ+NZ | 合計10分程度(チリが約7分でこの中では最も時間がかかる。他は数秒〜2分) |
| `5_daily_update.bat` | `python run_all.py daily` | 毎日更新用。ソースごとに「全期間」または「直近2年」のどちらかで差分更新 | 上記より短時間(直近2年分のみのソースがあるため) |

**引き継ぎ資料**:より詳しい設計判断の経緯は`~/my_ai_team/advisory_usda_project.md`、および
`~/Desktop/USDA_PSD_Data/引き継ぎ用PowerPoint_20260824.pptx`・`引き継ぎメモ_20260823.md`を
参照してください。

---

以上で移行手順は完了です。CEOへの報告時は、手順4で対象17ファイルの置換が0件に減ったこと
(4-5の実行結果)と、手順6の動作確認が成功したことの2点を必ず伝えてください。
