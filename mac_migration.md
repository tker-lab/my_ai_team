# Mac移行手順書

CEOの新しいMacBookへ、AIチーム拠点フォルダ `my_ai_team` を移行するための手順書です。
コマンドは1行ずつコピペできる形にしてあります。各手順に「これは何をしているか」を添えています。

**Macのユーザー名は `takahashitakayuki` に確定しています。**
最初にターミナル(Macの黒い画面のアプリ。コマンドを打ち込む場所)を開き、下記コマンドで名前が一致することだけ確認してください。

```
whoami
```

→ `takahashitakayuki` と表示されればOKです(違う場合はこの手順書の中の `takahashitakayuki` を実際の名前に読み替えてください)。

---

## 0. 事前に用意するもの:USBメモリ

この手順書では複数回(手順3・4・7)USBメモリを使ってファイルを運びます。合計するとそれなりの容量になるため、**32GB以上のUSBメモリを用意しておくことを推奨**します。

- USDA_PSD_Data(顧問部データ、手順4):実測約7.1GB
- 秘書メモリ・会話ログ(手順3):約134MB
- 機密ファイル4件・効果音素材(手順4):数十MB程度
- whisperモデル(手順7、USBでコピーする場合):約3GB

**参考:** 古い形式のUSBメモリ(FAT32形式)は1ファイルあたり4GB未満という制限がありますが、今回運ぶファイルはUSDA_PSD_Data側で確認されている最大の単体ファイルが約0.39GB、whisperのモデルファイルでも約3GBと、いずれもこの制限より小さいため、FAT32のままで問題ありません。

---

## 1. Macの下準備(Homebrew・Node.js・Claude Code)

VS Codeと拡張機能は導入済みとのことなので、ここでは残り3つを入れます。

### 1-1. Homebrewのインストール
Homebrewとは、Macでソフトウェアをコマンド一発でインストールできるようにする「アプリストアのコマンド版」のようなツールです。この後のNode.jsのインストールに使います。

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

実行後、ターミナルに「Next steps」として2行程度のコマンドが表示されることがあります。表示された通りにコピペして実行してください(PATHを通す設定です)。

### 1-2. Node.jsのインストール
Node.jsは、JavaScriptというプログラミング言語をパソコン上で動かすための実行環境です。Claude Code本体を動かすのに必要です。

```
brew install node
```

### 1-3. Claude Code本体のインストール
```
npm install -g @anthropic-ai/claude-code
```
`npm install -g` の `-g` は「このMac全体で使えるようにインストールする」という意味です。

### 1-4. Pythonとライブラリのインストール
顧問部(advisory-team)が使うUSDA_PSD_Dataのスクリプトは、Pythonというプログラミング言語で書かれており、`pandas`(表計算処理)・`openpyxl`(Excelファイル操作)・`requests`(インターネット通信)・`python-dotenv`(設定ファイルの読み込み)・`comtradeapicall`(貿易統計データ取得)という追加ライブラリ(拡張機能)を使います。macOS標準のPythonにはこれらが入っていないため、インストールが必要です。これを飛ばすと**顧問部の実務がMac初日から動きません**。

```
brew install python
```
```
python3 -m venv ~/my_ai_team_venv
```
```
source ~/my_ai_team_venv/bin/activate
```
```
pip install pandas openpyxl requests python-dotenv comtradeapicall
```

「仮想環境(venv)」とは、このプロジェクト専用のPython環境を他と分けて作る仕組みです。他のアプリ用に別のバージョンのライブラリを入れても影響し合わないようにするためのものです。`source ~/my_ai_team_venv/bin/activate` を実行すると、以後そのターミナルではこの専用環境が使われます(ターミナルを閉じるともとに戻るので、USDA_PSD_Dataのスクリプトを使う前には毎回このコマンドを実行してください)。

---

## 2. リポジトリのpublishとMacへのclone

GitHub Desktopを使って、Windows側で作ったGitリポジトリ(バージョン管理された`my_ai_team`フォルダ)をGitHub経由でMacに持っていきます。

### 2-1. Windows側:publish前に、全ての変更をコミットする
GitHub Desktopを開き、左側の「Changes」欄に変更中のファイルが残っていないか確認してください。残っている場合は、下部にコミットメッセージ(変更内容の一言メモ)を入力し、「Commit to main」ボタンを押してコミットを完了させてください。**publishは「最後にコミットした内容」をアップロードする操作**なので、直した内容がコミットされていないと、その修正が反映されないままGitHubに公開されてしまいます。

> **重要:** Gitは「今のファイル」だけでなく「過去の全ての状態」を記録して持っていきます。一度コミットしたものは、後からファイルを直しても履歴からは消えません。機密情報を含む状態でコミットしてしまった場合は、ファイルを直すだけでは不十分で、履歴そのものを作り直す必要があります。

### 2-2. Windows側:GitHubにpublish(アップロード)
1. GitHub Desktopを開く
2. 左上の「Current Repository」から `my_ai_team` を選ぶ(一覧に無ければ「Add Local Repository」で `C:\Users\PC_User\my_ai_team` を追加)
3. 「Publish repository」ボタンを押す
4. **ダイアログの「Keep this code private」に必ずチェックが入っていることを確認してから** Publish を実行

「publish」は、手元のGitリポジトリの複製をGitHub上に作ってアップロードする操作です。「private」にしておかないとCEO以外の誰でも見られる状態になってしまうため、ここは特に確認してください。

### 2-3. Mac側:GitHub Desktopをインストールしてclone
1. https://desktop.github.com/ からGitHub Desktopをダウンロード・インストール
2. CEOのGitHubアカウントでログイン
3. 「Clone a repository from the Internet」を選び、`my_ai_team` を選択
4. 保存先(Local Path)を `/Users/takahashitakayuki/my_ai_team` に指定してClone

「clone」は、GitHub上にあるリポジトリをそのままMacにダウンロードしてくる操作です。

---

## 3. 秘書メモリ・会話ログの移送(最重要)

秘書(CLAUDE.mdに基づくAIチームの司令塔役)がこれまで覚えてきた記憶や会話履歴は、Gitリポジトリの**外側**、`C:\Users\PC_User\.claude\projects\` の中にあります。ここはGit管理していないので、USBメモリなど物理メディアで手動コピーする必要があります。

### 3-1. Windows側:USBへコピー
以下のフォルダを丸ごとUSBメモリにコピーしてください。

```
C:\Users\PC_User\.claude\projects\c--Users-PC-User-my-ai-team
```

### 3-2. Mac側:フォルダ名を変えて配置
USBがMacに挿さると `/Volumes/USBの名前` として認識されます。以下のコマンドでコピーします(`USBの名前` の部分は実際の名前に置き換えてください)。

```
mkdir -p ~/.claude/projects
```
```
cp -R "/Volumes/USBの名前/c--Users-PC-User-my-ai-team" ~/.claude/projects/-Users-takahashitakayuki-my-ai-team
```

**なぜフォルダ名が重要か:** Claude Codeは、プロジェクトの記憶を「プロジェクトの絶対パスを元にした名前」のフォルダに保存する仕組みです。Windows側では `C:\Users\PC_User\my_ai_team` というパスが `c--Users-PC-User-my-ai-team` という名前に変換されていました。Mac側では `/Users/takahashitakayuki/my_ai_team` というパスになるので、変換後の名前は `-Users-takahashitakayuki-my-ai-team` になります。**この名前が1文字でもズレると、秘書は過去の記憶を一切読み込めず、初対面の状態からやり直しになります。** コピー後、フォルダ名を目視で再確認してください。

---

## 4. 機密ファイル・USDA_PSD_Data・効果音素材のUSBでの運搬

以下は「機密のためGitに載せていない」ファイル・フォルダ、および`.gitignore`で除外した`tools/`配下の素材です。Windows側でUSBにコピーし、Mac側の対応する場所に置いてください。

**Finderで隠しフォルダを表示する:** `.claude` から始まるフォルダは名前が「.」(ドット)で始まる「隠しフォルダ」で、Finderには初期状態では表示されません。対象のフォルダをFinderで開いた状態で `Cmd + Shift + .` を押すと表示/非表示が切り替わります(下記はターミナルのコマンドで完結するので、この操作自体は無くても進められます)。

### 4-1. Windows側:USBへコピー(PowerShellで実行)
USBのドライブレターは実際の値に置き換えてください(下記は `E:` の例)。

```
Copy-Item "C:\Users\PC_User\my_ai_team\advisory.md" "E:\advisory.md"
```
```
Copy-Item "C:\Users\PC_User\my_ai_team\advisory_usda_project.md" "E:\advisory_usda_project.md"
```
```
Copy-Item -Recurse "C:\Users\PC_User\my_ai_team\.claude\agent-memory\advisory-team" "E:\advisory-team"
```
```
Copy-Item "C:\Users\PC_User\my_ai_team\life_team.md" "E:\life_team.md"
```
```
Copy-Item -Recurse "C:\Users\PC_User\Desktop\USDA_PSD_Data" "E:\USDA_PSD_Data"
```
```
Copy-Item "C:\Users\PC_User\.claude\keybindings.json" "E:\keybindings.json"
```
```
Copy-Item -Recurse "C:\Users\PC_User\my_ai_team\tools\sound_effects" "E:\sound_effects"
```

### 4-2. Mac側:配置(ターミナルで実行)
USBが `/Volumes/USBの名前` として認識されている前提です(`USBの名前` は実際の名前に置き換えてください)。

```
cp "/Volumes/USBの名前/advisory.md" ~/my_ai_team/advisory.md
```
```
cp "/Volumes/USBの名前/advisory_usda_project.md" ~/my_ai_team/advisory_usda_project.md
```
```
mkdir -p ~/my_ai_team/.claude/agent-memory
```
```
cp -R "/Volumes/USBの名前/advisory-team" ~/my_ai_team/.claude/agent-memory/advisory-team
```
```
cp "/Volumes/USBの名前/life_team.md" ~/my_ai_team/life_team.md
```
```
cp -R "/Volumes/USBの名前/USDA_PSD_Data" ~/Desktop/USDA_PSD_Data
```
```
cp "/Volumes/USBの名前/keybindings.json" ~/.claude/keybindings.json
```
```
mkdir -p ~/my_ai_team/tools
```
```
cp -R "/Volumes/USBの名前/sound_effects" ~/my_ai_team/tools/sound_effects
```

これらはリポジトリに含めていないため、`git clone`(手順2)では一切コピーされません。配置し忘れると、顧問部が機能しなくなる・USDA_PSD_Dataのリポジトリ履歴が失われる・動画部が選定中の効果音素材(`cutin_bell.mp3`・`ending_bgm.mp3`)を失う、といったことが起きるので注意してください。

USDA_PSD_Data内のWindows専用パスの直し方は手順8で扱います。

---

## 5. グローバル設定の再現

Claude Code全体の設定ファイル `~/.claude/settings.json` をMac側に新規作成します。ターミナルで以下のコマンドを実行してください(Windows側の設定と同じ内容がファイルとして作られます)。

```
mkdir -p ~/.claude
```
```
cat > ~/.claude/settings.json << 'EOF'
{"autoUpdatesChannel":"latest","theme":"dark","agentPushNotifEnabled":true}
EOF
```

`cat > ファイル名 << 'EOF' ... EOF` は、`<< 'EOF'` と `EOF` の間に書いた文字列をそのままファイルに書き込むコマンドです。

キーバインドについては手順4で運搬済みです。

**注記:** Windows側にあった `.claude/settings.local.json`(プロジェクトごとのローカル権限設定。Windows専用のPowerShell許可ルール1件と、WebSearch・WebFetchの許可1件が入っていました)は`.gitignore`で除外しており、Macには引き継がれません。実害は小さいですが、**Mac側でClaude Codeを使い始めると、これまで許可済みだった操作の確認プロンプトが再び表示される**ことがあります。心当たりのない確認が出ても異常ではないので、内容を見て許可するかどうか判断してください。

---

## 6. 移せないので再実行が必要なもの

以下はセキュリティ上の理由(認証情報を平文でファイルに残さない設計)によりファイルコピーでは引き継げません。Mac側で最初に `claude` を起動した後、それぞれ再実行してください。

- **Anthropicアカウントへのログイン**:`claude` 起動後、`/login` を実行してブラウザでログイン
- **Notion MCP(NotionをAIから操作できるようにする連携機能)の再認証**:`/mcp` を実行し、画面の指示に従って再認証
- **Codexの再ログイン**:Codexを利用している場合、そのアプリ/CLIで再度ログイン操作

---

## 7. Whisper(音声文字起こしAI)のMac向け再構築

`tools/whisper/` にあった `ggml-large-v3.bin`(約3GB)・`ggml-small.bin`(488MB)は、**whisper.cpp**(Whisperを軽量・高速に動かすための実装。Apple Siliconの高速化機能(Metal)に対応)用のモデルファイルです。秘書が公式README(https://github.com/ggml-org/whisper.cpp)で確認済みの、現行の正しい手順です。

### 7-1. モデルファイルの入手方法(2択・USBでのコピーを推奨)
ggml形式のモデルファイルはOS非依存(WindowsでもMacでもそのまま使えるファイル形式)のため、**Windows側の実物をUSBでコピーする方法を推奨します**(再ダウンロードより早く、通信量もかかりません)。

- **推奨:USBでコピー** — `C:\Users\PC_User\my_ai_team\tools\whisper\ggml-large-v3.bin`(約3GB)と `ggml-small.bin`(488MB)をUSBにコピーし、Mac側の `~/my_ai_team/tools/whisper.cpp/models/` に配置(このフォルダは次の7-2のcloneで作られます)
- **代替:再ダウンロード** — 7-3のコマンドでネットから再取得

**重要:モデルファイルの置き場所が変わります。** 旧:`tools/whisper/ggml-large-v3.bin` → 新:`tools/whisper.cpp/models/ggml-large-v3.bin`。

### 7-2. whisper.cppの取得とビルド
```
brew install cmake
```
```
git clone https://github.com/ggml-org/whisper.cpp.git ~/my_ai_team/tools/whisper.cpp
```
```
cd ~/my_ai_team/tools/whisper.cpp && cmake -B build
```
```
cd ~/my_ai_team/tools/whisper.cpp && cmake --build build -j --config Release
```
`cmake` は、ソースコードからMac(Apple Silicon)向けの実行ファイルを組み立てるツールです。Apple Siliconでは高速化機能(Metal)が既定で自動的に有効になります。ビルドが完了すると、実行ファイルは `./build/bin/whisper-cli` に作られます(古い手順にあった `./main` ではありません)。

### 7-3. モデルファイルの再ダウンロード(USBでコピーしなかった場合のみ)
```
cd ~/my_ai_team/tools/whisper.cpp && sh ./models/download-ggml-model.sh large-v3
```
```
cd ~/my_ai_team/tools/whisper.cpp && sh ./models/download-ggml-model.sh small
```
ダウンロードされたモデルは `whisper.cpp/models/` フォルダに保存されます。

**注意:** 具体的な呼び出しコマンド(実際に文字起こしを実行する際のオプション等)は動画部のメモやワークフローに依存します。動作しない場合は動画部に確認のうえ調整してください。

---

## 8. Windows専用パスの置換(全18箇所・17ファイル)

**調査済み事実では「17箇所・16ファイル」とされていましたが、実際にgrepし直したところ `ai_team_operation_design.md` にも1箇所見つかり、正しくは合計18箇所・17ファイルでした。** 以下がその全リストです(Git管理外の顧問部ファイル分も、手順4でUSB移送した後にMac側で直す前提で含めています)。

置換の考え方:`C:\Users\PC_User\...`(バックスラッシュ区切り)→ `/Users/takahashitakayuki/...`(スラッシュ区切り)。

### Git管理下のファイル(3ファイル・4箇所)

| ファイル:行 | 置換前 | 置換後 |
|---|---|---|
| `youtube_team.md:135` | `C:\Users\PC_User\Desktop\動画保存\` | `/Users/takahashitakayuki/Desktop/動画保存/` |
| `youtube_team_video1.md:74` | `C:\Users\PC_User\Desktop\チャンネル素材\intro_slide_couple.png` | `/Users/takahashitakayuki/Desktop/チャンネル素材/intro_slide_couple.png` |
| `youtube_team_video1.md:75` | `C:\Users\PC_User\Desktop\チャンネル素材\intro_slide_design.html` | `/Users/takahashitakayuki/Desktop/チャンネル素材/intro_slide_design.html` |
| `ai_team_operation_design.md:222` | `c:\Users\PC_User\my_ai_team\.claude\settings.json` | `/Users/takahashitakayuki/my_ai_team/.claude/settings.json` |

### Git管理外(顧問部)のファイル(14ファイル・14箇所、`.claude/agent-memory/advisory-team/` 配下)

すべて `C:\Users\PC_User\Desktop\USDA_PSD_Data`(一部は末尾にサブパスが付く)を `/Users/takahashitakayuki/Desktop/USDA_PSD_Data` に置き換えます。

| ファイル:行 | 置換前 | 置換後 |
|---|---|---|
| `project_mla_chunk_progress.md:8` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` | `/Users/takahashitakayuki/Desktop/USDA_PSD_Data` |
| `project_mla_comtrade_report1_verification.md:12` | `C:\Users\PC_User\Desktop\USDA_PSD_Data\_検証_mla_report1\` | `/Users/takahashitakayuki/Desktop/USDA_PSD_Data/_検証_mla_report1/` |
| `project_frequency_column_addition.md:10` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` | `/Users/takahashitakayuki/Desktop/USDA_PSD_Data` |
| `project_brazil_format13col.md:9` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` | `/Users/takahashitakayuki/Desktop/USDA_PSD_Data` |
| `project_freshness_timing_survey.md:10` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` | `/Users/takahashitakayuki/Desktop/USDA_PSD_Data` |
| `project_mla_translation_completion.md:8` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` | `/Users/takahashitakayuki/Desktop/USDA_PSD_Data` |
| `project_mla_headcount_r67_delete.md:8` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` | `/Users/takahashitakayuki/Desktop/USDA_PSD_Data` |
| `project_psd_config_and_update_policy.md:8` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` | `/Users/takahashitakayuki/Desktop/USDA_PSD_Data` |
| `project_mla_dedup_scope_narrowing.md:8` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` | `/Users/takahashitakayuki/Desktop/USDA_PSD_Data` |
| `project_mla_unit_matrix.md:10` | `C:\Users\PC_User\Desktop\USDA_PSD_Data\MLA指標別_集計単位一覧.xlsx` | `/Users/takahashitakayuki/Desktop/USDA_PSD_Data/MLA指標別_集計単位一覧.xlsx` |
| `project_psd_format2_conversion.md:8` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` | `/Users/takahashitakayuki/Desktop/USDA_PSD_Data` |
| `project_run_all_psd_gap.md:8` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` | `/Users/takahashitakayuki/Desktop/USDA_PSD_Data` |
| `project_mla_report4_country_agg.md:8` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` | `/Users/takahashitakayuki/Desktop/USDA_PSD_Data` |
| `project_term_master_final_check.md:9` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` | `/Users/takahashitakayuki/Desktop/USDA_PSD_Data` |

これらのファイルはテキストエディタ(VS Code等)で開いて手動置換するか、VS Codeの「フォルダ内で検索・置換」機能で `C:\Users\PC_User` → `/Users/takahashitakayuki` の一括置換をかけたうえで、バックスラッシュがスラッシュに変わっていない箇所が残っていないか目視確認する方法でも構いません。

### USDA_PSD_Data側のパス置換(Pythonスクリプトが確実に失敗するため必須)

USBで運んだ `USDA_PSD_Data`(手順4)の中にも、Pythonスクリプトなどに `C:\Users\PC_User\...` のパスが直書きされています。**これを直さずにスクリプトを実行すると確実に失敗します。**

実測で判明している主な該当ファイル(件数が多いため代表例。同一内容のコピーが複数の出力フォルダに存在するものもあります):
- `build_freshness_report.py:13`
- `country_master.py:33`
- `freshness_timing_analysis.py:20`
- `_検証_mla_report1\compare.py:14`
- `README.txt:11`、`country_master.txt:33`(複数の出力フォルダに同一コピーあり)
- `引き継ぎメモ_20260823.md:4,11`
- `Codexレビュー_やり取りメモ.md:4`
- `ams_convert_log*.txt` などのログファイル群

件数が多いため、1件ずつ手で直すのではなく一括置換で対応します。**実行前に必ずUSDA_PSD_Dataフォルダ全体のバックアップ(コピー)を取ってください**(置換に失敗した場合に元へ戻せるようにするためです)。バックアップには元と同じ**約7.1GBの空き容量**が必要です。Macの空き容量(Appleメニュー→「このMacについて」→「ストレージ」で確認できます)が足りない場合は、外付けドライブなど別の場所にバックアップしてください。

```
cp -R ~/Desktop/USDA_PSD_Data ~/Desktop/USDA_PSD_Data_backup_before_replace
```

対象ファイルの一覧を確認します(このコマンドではファイルは変更されません)。`--exclude-dir=.git` はGitの内部管理フォルダを検索対象から外す指定、`-I` はバイナリファイル(csv/xlsx等の一部やコンパイル済みファイルなど、文字として読めないファイル)を対象から外す指定です。**この2つが無いと、後述の一括置換コマンドがUSDA_PSD_Dataのリポジトリ履歴を破損させたり、意図しないファイルの中身を壊したりする恐れがあるため必須です。**
```
grep -rlF --exclude-dir=.git -I 'C:\Users\PC_User\Desktop\USDA_PSD_Data' ~/Desktop/USDA_PSD_Data
```

一括置換を実行します:
```
grep -rlF --exclude-dir=.git -I 'C:\Users\PC_User\Desktop\USDA_PSD_Data' ~/Desktop/USDA_PSD_Data | while IFS= read -r f; do sed -i '' 's#C:\\Users\\PC_User\\Desktop\\USDA_PSD_Data#/Users/takahashitakayuki/Desktop/USDA_PSD_Data#g' "$f"; done
```

**macOSのsedは `-i` の直後に空文字の引数(`''`)を書く必要があります**(Linuxとは書き方が違うので注意。`-i ''` を書き忘れるとエラーになります)。置換後、上でリストされたファイルのうち何個かを開き、バックスラッシュ(`\`)がすべてスラッシュ(`/`)に変わっていることを目視確認してください。

**注意:大文字・小文字の違いは拾えません。** 上記のコマンドは大文字・小文字を区別するため、`c:\users\pc_user\...` のような小文字表記(このドキュメントの手順8冒頭にある `ai_team_operation_design.md:222` の実例のように、実際に小文字表記が使われているケースがあります)は検出できません。念のため、次のコマンドで小文字表記が無いか事前に洗い出しておくと安心です(`-i` は大文字小文字を区別しないという意味で、上のバックアップの`-i`とは無関係です)。

```
grep -rliF --exclude-dir=.git -I 'c:\users\pc_user' ~/Desktop/USDA_PSD_Data
```

ヒットするファイルがあれば、その表記に合わせて個別に確認・置換してください。

**注記:** `.xlsx` などのExcelファイルの中に数式や外部リンクとしてパスが埋め込まれている可能性がありますが、これは未確認です。Excelファイルが正しく開けない・リンク切れになる場合は、そのファイルをExcelで開いて手動確認してください。

---

## 9. 動作確認チェックリスト

Mac側ですべての手順が終わったら、以下を確認してください。

- [ ] ターミナルで `cd ~/my_ai_team && claude` を実行し、Claude Codeが起動する
- [ ] 秘書としての挨拶メッセージが表示される(secretary.mdの内容に基づく振る舞いをしている)
- [ ] `knowledge.md`・`status.md` の内容を秘書が把握している(例:「今どの部署にフォーカスしていますか」と聞いて status.md の内容と一致する回答が返る)
- [ ] 秘書の過去の記憶が引き継がれている(例:秘書に「私の自宅住所は?」と聞き、正しく答えられるかCEO自身で確認する。正解はこの手順書には書きません。答えられれば手順3のメモリ移送が成功している証拠です)
- [ ] `/agents` コマンドで5部署(advisory-team, app-team, life-team, pr-team, youtube-team)が一覧に表示される
- [ ] `/mcp` でNotion連携が「接続済み」になっている(手順6の再認証後)
- [ ] 移行完了後、秘書からCEOに自宅住所と勤務先を改めて口頭で確認し、秘書メモリ(リポジトリ外)にのみ記録する

---

以上で移行手順は完了です。不明点があれば秘書(このAIチームのセッション)に確認してください。
