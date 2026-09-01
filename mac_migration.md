# Mac移行手順書

※ Mac側で初めて起動した場合は `START_HERE.md` から読んでください。

CEOの新しいMacBookへ、AIチーム拠点フォルダ `my_ai_team` を移行するための手順書です。
コマンドは1行ずつコピペできる形にしてあります。各手順に「これは何をしているか」を添えています。

## Mac側のClaudeへの指示(この手順書を読んでいるあなたへ)

この手順書はMacBook側で起動したClaude Code(あなた)が読み、環境構築作業を代行する前提で書かれています。作業を始める前に、以下を必ず守ってください。

- **あなたはまだ秘書ではありません。** `CLAUDE.md` に書かれた秘書としての振る舞い(部署への委譲ルールなど)はまだ適用しません。環境構築が終わるまでは、この手順書の実行役に徹してください。
- **上から順に実行し、各手順が完了したことを実際のコマンド出力で確認してから次に進んでください。** 手順を飛ばさないでください。
- **CEOはIT初心者です。** 専門用語には一言説明を添えてください。CEO自身の操作が必要な箇所(サインイン、ブラウザでの認証、質問への回答など)では、何をどう操作すればよいかを具体的に示したうえで、CEOの操作完了を待ってから次に進んでください。
- **勝手にやってはいけないこと**: `git push`(必ずCEOの確認を得てから)、`~/my_ai_team` の外にあるファイルの削除、Windows側への変更。
- **環境構築が完了したら**、手順書の最後にある「動作確認チェックリスト」を実施し、結果をCEOに報告してから、秘書としての振る舞いを開始してください。
- **作業中に詰まったら、勝手に回避策を試さず、CEOに状況を報告して指示を仰いでください。**

---

**Macのユーザー名は `takahashitakayuki` に確定しています。**
最初にターミナル(Macの黒い画面のアプリ。コマンドを打ち込む場所)を開き、下記コマンドで名前が一致することだけ確認してください。

```
whoami
```

→ `takahashitakayuki` と表示されればOKです(違う場合はこの手順書の中の `takahashitakayuki` を実際の名前に読み替えてください)。

---

## 1. Macの下準備(Homebrew・Node.js・Claude Code)

VS Codeと拡張機能は導入済みとのことなので、ここでは残り3つを入れます。**先に行った棚卸しで既に入っていることが分かったものは、この節を飛ばして構いません。**

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

## 2. リポジトリの確認(Windows側の作業は完了済み)

**Windows側での作業はすでに完了しています。** GitHubへの公開(publish)も、その後の更新のアップロード(push)もWindows側で済んでおり、GitHub上にあるのが最新版です。あなた(Mac側のClaude)がこのファイルを読めているということは、CEOがすでにGitHub Desktop経由で `my_ai_team` リポジトリをMacに clone(GitHub上のリポジトリをそのままダウンロードしてくる操作)済みという前提です。改めてWindows側で何か操作する必要はありません。**CEOに「Publish repository」を押すよう案内しないでください。押すとGitHub上に別のリポジトリが2つ目できてしまいます。**

> **重要:** Gitは「今のファイル」だけでなく「過去の全ての状態」を記録して持っています。一度コミットしたものは、後からファイルを直しても履歴からは消えません。機密情報を含む状態でコミットしてしまった場合は、ファイルを直すだけでは不十分で、履歴そのものを作り直す必要があります(今後Mac側で作業する際も、この点は覚えておいてください)。

### 整合性の確認
念のため、Mac側で以下を実行し、正しいリポジトリを見ていること・最新のコミットを取得できていることを確認してCEOに報告してください。

```
cd ~/my_ai_team && git remote -v
```
```
cd ~/my_ai_team && git log --oneline -1
```

`git remote -v` で `origin` の参照先が `https://github.com/takataka0307/my_ai_team.git` になっていること、`git log --oneline -1` で何らかのコミットが表示されることを確認できれば十分です。**秘書メモリ(`secretary_memory`フォルダ)もリポジトリの中にあるため、このclone で一緒にMacへ来ています**(機微な2ファイルだけは`.gitignore`で除外されているため来ません。手順3で扱います)。

---

## 3. 秘書メモリ(機微2件)の作成と、効果音mp3の扱い

Windows・Macの2台を同じように使えるようにする設計では、次の4層に分けて扱っています。

- 層1(ルール・スキル・部署ファイル・部署メモリ)と層2(秘書メモリ)→ GitHubで同期(手順2のcloneで完了)
- 層3(大容量データ)→ 同期せず、部署ごとに担当マシンを固定(詳細は手順4)
- 層4(会話ログ)→ 同期しない(割り切り)

このうち、**秘書メモリの中の機微な2ファイルだけは `.gitignore` でGitから除外している**ため、cloneでは来ません。ファイル転送では運ばず、**あなた(Mac側のClaude)がCEOに直接質問して、その場で `secretary_memory/` 配下に作成**します。これがもともとの設計どおりの段取りです(機微情報は各マシンにローカル保存し、Gitには載せません)。

### 3-1. CEOに聞いて秘書メモリを作成する

CEOに、①自宅住所 ②食事に関する制約(ファイル名 `ceo-gluten-free-diet.md` から内容の見当はつきますが、詳細はCEOに直接聞いてください)の2点を口頭で確認してください。**回答内容をこのファイルや他のGit管理下のファイルに書き写さないこと**(このやり取り自体は会話ログに残りますが、会話ログはGit同期対象外です)。

聞き終えたら、以下の2ファイルを `secretary_memory/` 配下に作成してください。

```
~/my_ai_team/secretary_memory/ceo-home-address.md
~/my_ai_team/secretary_memory/ceo-gluten-free-diet.md
```

**書式は、既にリポジトリに入っている他の秘書メモリファイルに揃えてください。** 実際に `~/my_ai_team/secretary_memory/always-give-eta.md` を開いて中身を確認し、同じ構成(フロントマターの `name` / `description` / `metadata.type` と、本文の「事実」「**Why:**」「**How to apply:**」の構成)で作成してください。`type` はいずれも `user` としてください(住所・食事制約はCEO自身に関する情報のため)。

作成後、`secretary_memory/MEMORY.md`(索引ファイル)にこの2件へのリンク行が既にあることを確認してください(すでに `ceo-home-address.md`・`ceo-gluten-free-diet.md` へのリンクが載っているはずなので、通常は追記不要です)。

### 3-2. 効果音mp3は後回しでよい

動画部が選定中の効果音素材(`cutin_bell.mp3`・`ending_bgm.mp3`)は、**CEOが自分宛にメールで添付して送り、Mac側で手動配置する**方法に決まりました。**動画部の作業を始めるまでは不要**なので、この移行作業の中で急いで行う必要はありません。配置先だけ示しておきます。

```
~/my_ai_team/tools/sound_effects/cutin_bell.mp3
~/my_ai_team/tools/sound_effects/ending_bgm.mp3
```

**秘書メモリのリンクを張る手順は次の手順5で扱います(先に3-1のファイル作成を終えてから行ってください)。**

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

表示される一覧に、手順3で配置した `ceo-home-address.md` へのリンク行が含まれていれば(索引ファイルなので中身までは表示されません)、リンクとファイル配置の両方が成功しています。

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

**モデルファイルはMac側で再ダウンロードします。** 約3GBあり、Windowsから個別に転送する手段は用意していないため、ネットからの再取得手順を使います。

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

## 9. Windows専用パスの置換(実作業は4箇所・3ファイル)

**調査済み事実では「17箇所・16ファイル」とされていましたが、実際にgrepし直したところ `ai_team_operation_design.md` にも1箇所見つかり、経緯としての総数は合計18箇所・17ファイルでした。** ただし顧問部をWindows据え置きにした方針変更により、そのうち14箇所(顧問部メモリ分、Macには来ない)は作業不要です。**Mac側で実際に直すのは下記「Git管理下のファイル」の4箇所・3ファイルだけ**です。以下がその全リストです(参考記録として不要になった14箇所も残しています)。

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
- [ ] 秘書の過去の記憶が引き継がれている(例:秘書に「私の自宅住所は?」と聞き、正しく答えられるかCEO自身で確認する。正解はこの手順書には書きません。答えられれば手順3のファイル作成と手順5のリンク作成が成功している証拠です)
- [ ] `/agents` コマンドで5部署(advisory-team, app-team, life-team, pr-team, youtube-team)が一覧に表示される
- [ ] `/mcp` でNotion連携が「接続済み」になっている(手順7の再認証後)
- [ ] 手順3で自宅住所・食事の制約は確認済みのはずなので、**勤務先の会社名だけ**改めてCEOに口頭で確認し、秘書メモリ(機微ファイルなのでGit同期対象外)にのみ記録する。手順3をまだ行っていなければ、自宅住所・食事の制約もあわせてここで確認する

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
