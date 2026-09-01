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

## 0. ファイル転送の手段:LocalSend

この手順書では手順3で少量のファイル(秘書メモリの機微2件・効果音mp3 2件)をWindowsからMacへ運びます。CEOはクラウドドライブもUSBメモリも使わないため、**LocalSend**(同じWi-Fi上にある2台の間でファイルを直接送れる無料アプリ。クラウドを経由しないので登録や容量制限がありません)を使います。

### 0-1. 両OSへの導入
- Windows: https://localsend.org/ からWindows版をダウンロードしてインストール
- Mac: 同じく https://localsend.org/ からMac版をダウンロードしてインストール(Mac App Storeからも入手できます)

### 0-2. 送り方(共通の流れ)
1. WindowsとMac両方でLocalSendを起動する(同じWi-Fiに両方が繋がっていることを確認)
2. 起動しているMacが、Windows側の画面に「端末一覧」として自動的に出てくる
3. Windows側でLocalSendの画面に送りたいファイルをドラッグ&ドロップ(または「ファイルを選択」)する
4. 送り先としてMacの端末名を選び、送信する
5. Mac側に受信の確認ポップアップが出るので「承認」する。保存先は既定で「ダウンロード」フォルダになります

前提として、2台が同じWi-Fiルーターに繋がっている必要があります(スマホのテザリングなど別回線だと端末が見えません)。

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

### 1-4. Pythonとライブラリのインストール(顧問部を使う場合のみ)

**方針:顧問部(advisory-team)の作業は今後もWindows側に据え置きます。** データ量(約7.1GB)が大きく同期に向かないため、顧問部だけは「担当マシン固定」の運用としました。したがってMac側でこの1-4を行う必要は基本的にありません。将来Mac側でも顧問部の作業をする方針に変わった場合にのみ、以下を実施してください。

顧問部が使うUSDA_PSD_Dataのスクリプトは、Pythonというプログラミング言語で書かれており、`pandas`(表計算処理)・`openpyxl`(Excelファイル操作)・`requests`(インターネット通信)・`python-dotenv`(設定ファイルの読み込み)・`comtradeapicall`(貿易統計データ取得)という追加ライブラリ(拡張機能)を使います。

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

「仮想環境(venv)」とは、このプロジェクト専用のPython環境を他と分けて作る仕組みです。他のアプリ用に別のバージョンのライブラリを入れても影響し合わないようにするためのものです。`source ~/my_ai_team_venv/bin/activate` を実行すると、以後そのターミナルではこの専用環境が使われます(ターミナルを閉じるともとに戻るので、使う前には毎回このコマンドを実行してください)。

---

## 2. リポジトリのpublishとMacへのclone

GitHub Desktopを使って、Windows側で作ったGitリポジトリ(バージョン管理された`my_ai_team`フォルダ)をGitHub経由でMacに持っていきます。**秘書メモリ(`secretary_memory`フォルダ)もリポジトリの中にあるため、このcloneで一緒にMacへ来ます**(機微な2ファイルだけは除く。手順3で別途運びます)。

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

## 3. 秘書メモリ(機微2件)・効果音mp3のLocalSend移送

Windows・Macの2台を同じように使えるようにする設計では、次の4層に分けて扱っています。

- 層1(ルール・スキル・部署ファイル・部署メモリ)と層2(秘書メモリ)→ GitHubで同期(手順2のcloneで完了)
- 層3(大容量データ)→ 同期せず、部署ごとに担当マシンを固定(詳細は手順4)
- 層4(会話ログ)→ 同期しない(割り切り)

このうち、**秘書メモリの中の機微な2ファイルだけは `.gitignore` でGitから除外している**ため、cloneでは来ません。この手順でLocalSendを使って個別に運びます。運ぶのはこの2件と、動画部が選定中の効果音mp3 2件だけです。

### 3-1. Windows側:LocalSendで送る
LocalSendを起動し、以下の4ファイルを選んでMacへ送信してください(手順0参照)。

```
C:\Users\PC_User\my_ai_team\secretary_memory\ceo-home-address.md
C:\Users\PC_User\my_ai_team\secretary_memory\ceo-gluten-free-diet.md
C:\Users\PC_User\my_ai_team\tools\sound_effects\cutin_bell.mp3
C:\Users\PC_User\my_ai_team\tools\sound_effects\ending_bgm.mp3
```

### 3-2. Mac側:受信したファイルを正しい場所に配置
LocalSendで受信したファイルは既定で「ダウンロード」フォルダに保存されます。ターミナルで以下を実行し、正しい置き場所に移動してください。

```
mv ~/Downloads/ceo-home-address.md ~/my_ai_team/secretary_memory/ceo-home-address.md
```
```
mv ~/Downloads/ceo-gluten-free-diet.md ~/my_ai_team/secretary_memory/ceo-gluten-free-diet.md
```
```
mkdir -p ~/my_ai_team/tools/sound_effects
```
```
mv ~/Downloads/cutin_bell.mp3 ~/my_ai_team/tools/sound_effects/cutin_bell.mp3
```
```
mv ~/Downloads/ending_bgm.mp3 ~/my_ai_team/tools/sound_effects/ending_bgm.mp3
```

配置し忘れると、秘書がCEOの自宅住所・食事制限を思い出せない状態になる、動画部が選定中の効果音素材を失う、といったことが起きるので注意してください。

**秘書メモリのリンクを張る手順は手順5で扱います(先に手順4のリポジトリ配置を終えてから行ってください)。**

---

## 4. 顧問部データはWindowsに据え置き(何もしなくてよい)

**顧問部(advisory-team)の作業は今後もWindows側で行う方針に決まりました。** 理由は、扱うデータ(`Desktop\USDA_PSD_Data`、実測約7.1GB)が大きく、2台の同期対象にすると管理が煩雑になるためです。

そのため、以下はMacに一切運びません。今後もWindows側にのみ存在し続けます。

- `C:\Users\PC_User\Desktop\USDA_PSD_Data`(顧問部の作業データ、別のGitリポジトリ)
- `advisory.md`・`advisory_usda_project.md`(顧問部の機密ファイル)
- `.claude\agent-memory\advisory-team\`(顧問部のメモリ)
- `life_team.md`(ライフサポート部の機密ファイル。こちらは層3ではなくCEO判断による機密扱いですが、同様にWindows限定です)

Mac側でこれらのファイルやフォルダを探しても存在しないのが正しい状態です。顧問部・ライフサポート部の作業をしたい時は、この2部署に関してはWindows機を開いてください。

---

## 5. 秘書メモリのリンクを張る(Mac側)

秘書(CLAUDE.mdに基づくAIチームの司令塔役)の記憶は、Windows側では次の2箇所を「ジャンクション」という仕組みでつないでいます。

- 実体:リポジトリの中の `secretary_memory` フォルダ(Gitで同期される)
- リンク:Claude Codeが実際に記憶を読みに行く `C:\Users\PC_User\.claude\projects\c--Users-PC-User-my-ai-team\memory`

Macでも同じ考え方で、**シンボリックリンク**(Macでのジャンクションに相当する仕組み。あるフォルダを、実体は別の場所にありながら、あたかもそこにあるかのように見せかける機能)を張ります。

### 5-1. リンク先の親フォルダを作る
シンボリックリンクを作るコマンドは、リンクを置く場所の「親フォルダ」が先に存在している必要があります(手順2のcloneで `~/my_ai_team` はできていますが、`~/.claude/projects/` 配下のプロジェクトフォルダはまだ無いので、これを先に作ります)。

```
mkdir -p ~/.claude/projects/-Users-takahashitakayuki-my-ai-team
```

**なぜこの名前か:** Claude Codeは、プロジェクトの記憶を「プロジェクトの絶対パスを元にした名前」のフォルダに保存する仕組みです。Mac側のプロジェクトパス `/Users/takahashitakayuki/my_ai_team` を変換すると `-Users-takahashitakayuki-my-ai-team` になります(Windows側で `C:\Users\PC_User\my_ai_team` が `c--Users-PC-User-my-ai-team` になっていたのと同じ規則です)。**この名前が1文字でもズレると、秘書は過去の記憶を一切読み込めません。**

### 5-2. シンボリックリンクを作る
```
ln -s /Users/takahashitakayuki/my_ai_team/secretary_memory /Users/takahashitakayuki/.claude/projects/-Users-takahashitakayuki-my-ai-team/memory
```

`ln -s リンク先の実体 作るリンクの場所` という書式です。実行後、以下のコマンドでリンクが正しく張れているか確認してください。

```
ls -la ~/.claude/projects/-Users-takahashitakayuki-my-ai-team/
```

`memory -> /Users/takahashitakayuki/my_ai_team/secretary_memory` のような行が表示されれば成功です。さらに次のコマンドで、リンク経由できちんと中身が読めるかも確認してください。

```
cat ~/.claude/projects/-Users-takahashitakayuki-my-ai-team/memory/MEMORY.md
```

手順3で配置した `ceo-home-address.md` の内容を含む一覧が表示されれば、リンクとファイル配置の両方が成功しています。

---

## 6. グローバル設定の再現

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

**注記:** Windows側にあった `.claude/settings.local.json`(プロジェクトごとのローカル権限設定)は`.gitignore`で除外しており、Macには引き継がれません。実害は小さいですが、**Mac側でClaude Codeを使い始めると、これまで許可済みだった操作の確認プロンプトが再び表示される**ことがあります。心当たりのない確認が出ても異常ではないので、内容を見て許可するかどうか判断してください。

なお、キーバインド(`~/.claude/keybindings.json`)についてはこの移行では対象外としています。必要であればCEOに個別に確認してください。

---

## 7. 移せないので再実行が必要なもの

以下はセキュリティ上の理由(認証情報を平文でファイルに残さない設計)によりファイルコピーでは引き継げません。Mac側で最初に `claude` を起動した後、それぞれ再実行してください。

- **Anthropicアカウントへのログイン**:`claude` 起動後、`/login` を実行してブラウザでログイン
- **Notion MCP(NotionをAIから操作できるようにする連携機能)の再認証**:`/mcp` を実行し、画面の指示に従って再認証
- **Codexの再ログイン**:Codexを利用している場合、そのアプリ/CLIで再度ログイン操作

---

## 8. Whisper(音声文字起こしAI)のMac向け再構築

`tools/whisper/` にあった `ggml-large-v3.bin`(約3GB)・`ggml-small.bin`(488MB)は、**whisper.cpp**(Whisperを軽量・高速に動かすための実装。Apple Siliconの高速化機能(Metal)に対応)用のモデルファイルです。秘書が公式README(https://github.com/ggml-org/whisper.cpp)で確認済みの、現行の正しい手順です。

**方針変更:モデルファイルはMac側で再ダウンロードします。** クラウドドライブもUSBも使わない前提のため、約3GBのファイルをLocalSend経由で送るのは現実的ではありません。幸い、ネットからの再取得手順が確立しているため、そちらを使います。

**重要:モデルファイルの置き場所が変わります。** 旧:`tools/whisper/ggml-large-v3.bin` → 新:`tools/whisper.cpp/models/ggml-large-v3.bin`。

### 8-1. whisper.cppの取得とビルド
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

### 8-2. モデルファイルの再ダウンロード
```
cd ~/my_ai_team/tools/whisper.cpp && sh ./models/download-ggml-model.sh large-v3
```
```
cd ~/my_ai_team/tools/whisper.cpp && sh ./models/download-ggml-model.sh small
```
ダウンロードされたモデルは `whisper.cpp/models/` フォルダに保存されます。合計約3.5GBのダウンロードになるため、Wi-Fi環境で数分〜数十分程度かかる想定です。

**注意:** 具体的な呼び出しコマンド(実際に文字起こしを実行する際のオプション等)は動画部のメモやワークフローに依存します。動作しない場合は動画部に確認のうえ調整してください。

---

## 9. Windows専用パスの置換(全18箇所・17ファイル)

**調査済み事実では「17箇所・16ファイル」とされていましたが、実際にgrepし直したところ `ai_team_operation_design.md` にも1箇所見つかり、正しくは合計18箇所・17ファイルでした。** 以下がその全リストです。

置換の考え方:`C:\Users\PC_User\...`(バックスラッシュ区切り)→ `/Users/takahashitakayuki/...`(スラッシュ区切り)。

### Git管理下のファイル(3ファイル・4箇所)

| ファイル:行 | 置換前 | 置換後 |
|---|---|---|
| `youtube_team.md:135` | `C:\Users\PC_User\Desktop\動画保存\` | `/Users/takahashitakayuki/Desktop/動画保存/` |
| `youtube_team_video1.md:74` | `C:\Users\PC_User\Desktop\チャンネル素材\intro_slide_couple.png` | `/Users/takahashitakayuki/Desktop/チャンネル素材/intro_slide_couple.png` |
| `youtube_team_video1.md:75` | `C:\Users\PC_User\Desktop\チャンネル素材\intro_slide_design.html` | `/Users/takahashitakayuki/Desktop/チャンネル素材/intro_slide_design.html` |
| `ai_team_operation_design.md:222` | `c:\Users\PC_User\my_ai_team\.claude\settings.json` | `/Users/takahashitakayuki/my_ai_team/.claude/settings.json` |

### Git管理外(顧問部)のファイル(14ファイル・14箇所、`.claude/agent-memory/advisory-team/` 配下)

**この節は参考情報です。方針変更により顧問部データはWindowsに据え置くため、これらのファイルはMacに存在せず、置換作業自体が不要になりました。** 将来的に顧問部データをMacへ移す方針に変わった場合に備えて、対象箇所の記録だけ残します。

すべて `C:\Users\PC_User\Desktop\USDA_PSD_Data`(一部は末尾にサブパスが付く)を `/Users/takahashitakayuki/Desktop/USDA_PSD_Data` に置き換えるものでした。

| ファイル:行 | 置換前 |
|---|---|
| `project_mla_chunk_progress.md:8` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` |
| `project_mla_comtrade_report1_verification.md:12` | `C:\Users\PC_User\Desktop\USDA_PSD_Data\_検証_mla_report1\` |
| `project_frequency_column_addition.md:10` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` |
| `project_brazil_format13col.md:9` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` |
| `project_freshness_timing_survey.md:10` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` |
| `project_mla_translation_completion.md:8` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` |
| `project_mla_headcount_r67_delete.md:8` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` |
| `project_psd_config_and_update_policy.md:8` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` |
| `project_mla_dedup_scope_narrowing.md:8` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` |
| `project_mla_unit_matrix.md:10` | `C:\Users\PC_User\Desktop\USDA_PSD_Data\MLA指標別_集計単位一覧.xlsx` |
| `project_psd_format2_conversion.md:8` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` |
| `project_run_all_psd_gap.md:8` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` |
| `project_mla_report4_country_agg.md:8` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` |
| `project_term_master_final_check.md:9` | `C:\Users\PC_User\Desktop\USDA_PSD_Data` |

これらのファイルはテキストエディタ(VS Code等)で開いて手動置換するか、VS Codeの「フォルダ内で検索・置換」機能で `C:\Users\PC_User` → `/Users/takahashitakayuki` の一括置換をかけたうえで、バックスラッシュがスラッシュに変わっていない箇所が残っていないか目視確認する方法でも構いません。

---

## 10. 動作確認チェックリスト

Mac側ですべての手順が終わったら、以下を確認してください。

- [ ] ターミナルで `cd ~/my_ai_team && claude` を実行し、Claude Codeが起動する
- [ ] 秘書としての挨拶メッセージが表示される(secretary.mdの内容に基づく振る舞いをしている)
- [ ] `knowledge.md`・`status.md` の内容を秘書が把握している(例:「今どの部署にフォーカスしていますか」と聞いて status.md の内容と一致する回答が返る)
- [ ] 秘書の過去の記憶が引き継がれている(例:秘書に「私の自宅住所は?」と聞き、正しく答えられるかCEO自身で確認する。正解はこの手順書には書きません。答えられれば手順3・5の秘書メモリ移送とリンク作成が成功している証拠です)
- [ ] `/agents` コマンドで5部署(advisory-team, app-team, life-team, pr-team, youtube-team)が一覧に表示される
- [ ] `/mcp` でNotion連携が「接続済み」になっている(手順7の再認証後)
- [ ] 移行完了後、秘書からCEOに自宅住所と勤務先を改めて口頭で確認し、秘書メモリ(機微ファイルなのでGit同期対象外)にのみ記録する

### 部署ごとの担当マシン一覧
- **アプリ開発部・動画部** → Mac(開発機材・動画編集環境がMac側にあるため)
- **顧問部** → Windows据え置き(USDA_PSD_Dataが約7.1GBと大きく、同期しない方針のため)
- **広報部・ライフサポート部** → どちらでも可(大容量データを扱わないため)

---

## 11. 2台での日常運用

Windows・Macの2台を切り替えて使う際の運用ルールです。

- **作業開始時**:秘書が自動で `git pull`(GitHub上の最新の内容を手元に取り込む操作)を行います。CEOが意識して何かする必要はありません。
- **作業終了時**:秘書が自動で `git add`(変更をGitに記録する準備)→ `commit`(記録の確定)→ `push`(GitHubへのアップロード)を行います。これもCEOが意識する必要はありません。
- **唯一の注意点:2台を同時に使わないこと。** 例えばWindowsで作業中に、その変更をpushする前にMacでも同じファイルを編集してしまうと、どちらの内容を正とするか(「衝突」と呼ばれる状態)が発生し、手作業での解決が必要になります。1台を使い終えて閉じてから、もう1台を開くようにしてください。
- 顧問部・ライフサポート部の機密ファイルはそもそも同期対象外(手順4参照)なので、この衝突の心配はありません。

---

以上で移行手順は完了です。不明点があれば秘書(このAIチームのセッション)に確認してください。
