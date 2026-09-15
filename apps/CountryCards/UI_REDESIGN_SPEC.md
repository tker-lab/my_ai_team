# Country Cards Collection 全体UI/UX再設計仕様

- 文書状態: 実装指示に使用可能
- 対象: `apps/CountryCards/` のSwiftUI表示層
- 基準日: 2026-09-14
- 対応OS: iOS 17以降、iPhone縦向き
- 目的: iOS標準部品を並べた印象をなくし、承認済みガチャデモの「大自然・地球・嵐・光・収集」の世界観を、起動から図鑑・対戦・課金まで一貫させる

## 0. この仕様の優先順位と変更禁止事項

優先順位は次の通り。下位項目は上位項目を壊してはならない。

1. 既存の抽選確率、保存データ、課金、広告回数、対戦、Game Centerのロジックを維持する
2. CEO承認済みガチャデモの演出意図と操作フローを本体へ正しく移植する
3. 全画面を同じデザインシステムで作り直し、標準iOS画面に見える要因を取り除く
4. アクセシビリティ、端末差、処理性能を満たす
5. 装飾の細部を磨く

この再設計では次を変更しない。

- `GachaEngine` の確率、最低保証、HUR確率 `1/20,000,000`
- 1回3枚、通常3枚目SR以上、課金10連30枚目SSR以上、ポイント10連30枚目SR以上、ポイント100連300枚目SSR以上
- `DailyBonusManager` のログイン・広告・対戦報酬回数
- `OwnedCollection` の保存キー、所持判定、ダブりポイント、ユーザー名上限
- `BattleViewModel` の5ターン、要素重複なし、高低ランダム、CPU先出し、プレイヤー4択、同値引き分け、報酬判定
- 北朝鮮GDPの表示「データ非公開」、CPUのHUR排除、コレクション内での特別扱い
- Game Centerの3つのLeaderboard IDとスコア形式
- StoreKitの商品ID・購入処理、iCloud引き継ぎ方式、国カードのデータ
- iOS標準共有シートを使う方針

UIテストで使用中のアクセシビリティIDは原則維持する。画面構造上の都合で要素を置き換える場合も、`titleScreenTapArea`、`onboardingNameField`、`onboardingStartButton`、`gachaEntrance_*`、`gachaIntroArea`、`gachaSkipButton`、`gachaRevealArea`、`battleCandidateButton` は同じ操作対象へ付け直す。

## 1. 現行画面・主要コンポーネントの棚卸し

### 1.1 画面一覧

| 領域 | 現行ファイル | 現行構造 | 標準iOS感が強い具体箇所 |
|---|---|---|---|
| 起動 | `TitleScreenView.swift` | グラデーション、SF Symbolsの地球、タイトル、カプセル型タップ領域 | 主役が `globe.asia.australia.fill` そのもの。背景が2色グラデーションだけで、承認済みデモの地球・雨・光の奥行きがない |
| 初回名前登録 | `OnboardingNameView.swift` | `VStack`、SF Symbols、`.roundedBorder` TextField、ボタン | 標準TextFieldと標準的な中央寄せフォーム。ゲーム開始の儀式ではなく設定入力に見える |
| アプリ骨格 | `RootTabView.swift` | 標準 `TabView` 4タブ | 標準タブバー、SF Symbols、標準ラベルが全面に出る。ホーム画面がなく、起動後すぐ図鑑になる |
| 図鑑トップ | `CollectionHomeView.swift` | 標準セグメントPickerで国別・要素別切替 | `.segmented` と標準navigation titleが設定アプリに近い |
| 国一覧 | `CountryListView.swift` | `.insetGrouped` List、NavigationLink、旗、枚数 | グループ化List、標準余白、標準区切り、標準シェブロンが画面の大半を占める |
| 要素一覧 | `ElementListView.swift` | `.insetGrouped` List、色付きCircle | ほぼ設定一覧。要素の意味や収集の楽しさが色付き点だけでは伝わらない |
| 国詳細 | `CountryDetailView.swift` | カードグリッドと縦並び豆知識 | カード外の背景・章立てがなく、豆知識はLabelの羅列。ロック解除が報酬として見えない |
| 要素ランキング | `ElementRankingView.swift` | List、順位テキスト、標準行Button | 表計算的な一覧。上位、所持、未所持の視覚的な差が弱い |
| ガチャトップ | `GachaHomeView.swift` | NavigationStack、toolbar、Menu、alert、10個の入口カード | 「排出確率」が標準toolbar、「その他の引き方」が標準Menu、ログイン報酬が標準alert。入口はSF Symbolsの箱でデモの世界観と不一致 |
| 無料ガチャ | `GachaPlayView.swift` | 単色背景、SF Symbolsの箱、標準スキップ、単純なカード差し替え | 承認済みデモ未統合。導入・開封・反転・光が簡易表示のまま |
| ポイント要素選択 | `PointGachaElementListView.swift` | 標準List | ガチャ入口が設定一覧に見える |
| ポイントガチャ | `PointGachaView.swift` | 標準ボタン列、結果グリッド | 消費量、受取枚数、保証の優先度が弱い。結果に祝祭感がない |
| 課金要素選択 | `IAPGachaElementListView.swift` | 標準List | 商品選択より設定一覧に見える |
| 課金ガチャ | `IAPGachaView.swift` | 商品名、テキストリンク、`.borderedProminent`、結果グリッド | 購入内容・価格・保証が1つの商品パネルとしてまとまっていない |
| 排出確率 | `GachaOddsView.swift` | 複数Sectionの標準List | 法的に重要な内容は正しいが、画面全体が設定表。入口別保証を見落としやすい |
| 対戦トップ | `BattleHomeView.swift` | SF Symbolsの稲妻、説明文、開始ボタン | ゲームモード選択ではなく説明ページに見える。地球上の対戦という舞台がない |
| 対戦中 | `BattlePlayView.swift` | ScrollView、テキスト、Capsuleルール表示、Divider、カード | 情報は揃っているが、CPU=奥・自分=手前という空間性が弱い。勝敗演出は絵文字の雷が中心 |
| 対戦結果 | `BattlePlayView.swift` 内 | 勝敗テキスト、戦績、報酬文 | 1試合を終えた報酬・振り返りの画面として弱く、次の行動もない |
| プロフィール | `ProfileView.swift` | `.insetGrouped` List、Section、LabeledContent、標準alert | iOS設定画面に最も近い。王冠以外にゲームの所有感がない |
| 全国ランキング | `LeaderboardView.swift` | セグメントPicker、List、ProgressView | 標準コントロールの組合せ。上位3名や自分の位置に特別感がない |
| このアプリについて | `AboutView.swift` | 標準ListとSection | 情報は正しいが資料一覧に見える。データの出典と対象範囲の読み分けが弱い |
| カード詳細 | `CardDetailSheet.swift` | 標準sheet、NavigationStack、toolbarの「閉じる」 | カードを獲得・観察する場ではなく、標準プレビューシートに見える |
| 共有 | `ShareSheet.swift` | UIActivityViewController | ここはOS連携が目的なので標準のまま維持する。共有前の入口だけ独自化する |

### 1.2 現行共通コンポーネント

- `AppTheme`: 金〜オレンジの単一キーカラー、ライト/ダーク背景、Primary Button、Raised Cardのみ。色・余白・角丸・文字・モーションが別々の画面へ規則として渡っていない。
- `GamePrimaryButtonStyle`: すべてCapsuleのため、iOSのprominent buttonとの差が主に色だけ。副操作・報酬・危険・読取専用・loading状態の体系がない。
- `CardView`: 機能上は共用できているが、国旗画像、文字、レア色、要素枠が平面的に積まれている。固定 `160 x 220` と `scaleEffect` が各画面で繰り返される。
- `RarityBadge`: 小さなCapsule。色以外の形・模様・発光差がない。
- `RaisedCardBackground`: `.background` と標準的な影だけで、地球・観測・収集の意味を持たない。

### 1.3 標準iOS感の主因

単に「色が薄い」ことが原因ではない。次の構造を置き換える必要がある。

1. `TabView`、`.insetGrouped`、`.segmented`、標準toolbar、標準Menu、標準alertがページの輪郭を決めている
2. SF Symbolsが小さな補助アイコンではなく、画面の主役・ブランドマークになっている
3. 画面ごとに背景の舞台がなく、白地または単純なグラデーション上へ部品を置いている
4. すべての操作が「標準行をタップ」「カプセルボタンをタップ」で、収集・開封・対戦という行為の差がない
5. ヘッダー、資源表示、進捗、報酬、空状態、エラーの独自パターンがない
6. ガチャデモだけが暗い大気・地球・光を使い、本編と明度・質感・動きが別作品になっている

## 2. 世界観とデザイン原則

### 2.1 世界観

コンセプト名は実装内で「Earth Archive」とする。画面上へこの英語を必ず表示する必要はない。

プレイヤーは、嵐の中から世界各国の情報をカードとして観測・回収し、地球の記録庫を完成させていく。ガチャは「嵐からカードを回収する瞬間」、図鑑は「静かな観測記録庫」、対戦は「大気が衝突する観測フィールド」、プロフィールは「探査記録」と位置付ける。

画面間で舞台は変えるが、共通して次の3層を持つ。

- 深層: 夜の地球・海を思わせる濃紺
- 中層: 等高線、緯度経度、雨粒、雲などを5〜12%不透明度で置く
- 表層: 操作や報酬の周囲だけに白・シアン・金の光を集中させる

### 2.2 デザイン原則

1. **暗い世界に意味のある光を置く**: 常時すべてを光らせない。選択、入手、勝利、進捗のみに光を使う。
2. **情報は観測パネルとして見せる**: 標準Listではなく、濃紺の面、細い境界線、見出し、数値を一体化した独自パネルにする。
3. **色だけに頼らない**: レア度は色+枠形状+模様+ラベル、要素は色+固有記号+名称で区別する。
4. **カードが常に主役**: ナビゲーションや説明文より、カード・収集率・対戦カードの面積を優先する。
5. **静と動を分ける**: 通常画面は低速で落ち着き、ガチャと決着だけ強く動く。
6. **装飾より読めることを優先**: 数値、単位、勝利条件、価格、排出確率は装飾上でも常に4.5:1以上のコントラストを確保する。
7. **標準機能は裏側で使う**: NavigationStack、sheet、TextField等は機能として使用可。ただし標準外観を画面骨格として露出させない。

## 3. デザイントークン

### 3.1 色

すべてsRGBの基準値。ダークテーマを既定とし、今回ライトテーマ専用配色は作らない。端末がライト設定でもアプリ本編はこの配色を使う。

| 用途 | 名前 | Hex | 使用条件 |
|---|---|---:|---|
| 最深背景 | `earthAbyss` | `#040811` | 全画面の最下層 |
| 背景上部 | `earthNight` | `#071426` | 通常画面グラデーション開始 |
| 背景下部 | `deepOcean` | `#0A2638` | 通常画面グラデーション終了 |
| パネル | `panelBase` | `#0D1B2A` | 94%不透明以上。文字の背面 |
| 浮上パネル | `panelRaised` | `#12283A` | 選択・重要情報 |
| 境界線 | `lineQuiet` | `#274256` | 通常1pt、30〜70%不透明度 |
| 主文字 | `textPrimary` | `#F4FAFF` | タイトル・本文 |
| 副文字 | `textSecondary` | `#A8BDCC` | 注記。最小12pt |
| 無効文字 | `textDisabled` | `#667C8B` | 操作不能状態 |
| 地球アクセント | `earthCyan` | `#58D8E8` | 選択、リンク、通常の収束光 |
| 嵐アクセント | `stormBlue` | `#3A83FF` | 対戦・SSR導入の補助 |
| 収集・報酬 | `archiveGold` | `#F2C85B` | 報酬、コンプリート、UR |
| 成功 | `successGreen` | `#55D39A` | 勝利、解放、New |
| 警告 | `warningAmber` | `#F3A63C` | 残数低下、保留 |
| エラー | `dangerCoral` | `#FF6D67` | エラー、敗北。本文背景には使わない |
| SSR反転光 | `ssrViolet` | `#A96CFF` | 紫白の一度きりの閃光 |
| HUR補助光 | `hurCyan` | `#7DF3FF` | 金白に加える第3色 |

レア度のカード面は既存方針を保持しつつ次の値へ統一する。

| レア度 | 主色 | 副色 | 色以外の識別 |
|---|---:|---:|---|
| N | `#CDD7DC` | `#7F939E` | 単線枠、無地 |
| SR | `#48B875` | `#173C2A` | 二重線の下辺、斜め細線 |
| SSR | `#3F7FE5` | `#191F5A` | 角に4点の星刻印、弱い紫白光 |
| UR | `#9C56D8` | `#D7A83D` | 金属的な二重枠、金白光 |
| HUR | `#E0B33E` | `#071018` | 非対称の多重枠、金白青光、専用紋様 |

要素色はカード枠に濃淡を付けず1色で使う既存ルールを守る。色覚差へ備えて固有記号を必ず併記する。

| 要素 | Hex | 固有記号の意匠 |
|---|---:|---|
| 人口 | `#3788FF` | 3つの点と弧 |
| 子どもの割合 | `#FF6FAE` | 小円+成長線 |
| 人口増加率 | `#FF9D3D` | 上下矢印 |
| 平均寿命 | `#42D6BD` | 生命線 |
| 面積 | `#B98B62` | 等高線四角 |
| GDP | `#F05A5A` | 積層バー |
| 森林の割合 | `#47B96A` | 葉脈 |
| CO2排出量 | `#93A2AE` | 3つの雲粒 |
| 公用語の数 | `#A779E9` | 吹き出し2つ |
| 隣接国の数 | `#32C1C7` | 接続ノード |

### 3.2 タイポグラフィ

外部フォント追加を前提にしない。日本語はシステム日本語書体、英数字は `.rounded` または `.monospaced` を明示する。`Font.Design.rounded` は日本語グリフには効かないため、和文の個性は字間、太さ、周囲の装飾で作る。

| 役割 | 基準 | 行間・補足 |
|---|---|---|
| Display | 32pt / black | タイトル画面のみ、英字tracking -0.5〜0 |
| Screen title | 26pt / bold | 1行、長い場合22ptまで縮小 |
| Hero number | 30pt / heavy / monospacedDigit | 所持率、戦績、残数 |
| Section title | 17pt / bold | 上に24pt、下に10pt |
| Card country | 16pt / bold | 1行、minimumScaleFactor 0.65 |
| Body | 15pt / regular | lineSpacing 3 |
| Action | 16pt / bold | ボタン |
| Meta | 12pt / medium | 大文字英字はtracking 1.2、長文不可 |
| Caption | 11pt / regular | 出典等。Dynamic Typeで12pt未満に固定しない |

数字は `monospacedDigit()` を使い、カウント変化でレイアウトが揺れないようにする。日本語の漢字数値表記は既存 `displayValue` を維持する。

### 3.3 背景、質感、光

- 通常画面背景: `earthNight` → `deepOcean` の縦グラデーション。上部35%に地球弧、全体に等高線を不透明度6%、粒子を最大12個置く。
- 図鑑背景: 雨を止め、等高線と緯度経度を中心にする。情報を読む場なので最も静かにする。
- ガチャ背景: 承認済みデモの `EarthStormScene` を基準とする。
- 対戦背景: 上部CPU側を寒色、下部プレイヤー側を深い青緑にし、中央に水平の大気境界線を置く。
- パネル質感: 半透明ブラーを主体にしない。`panelBase` 94〜98% + 上端1ptの白8% + 下端1ptの黒20%で塗装面にする。
- 光: 通常時は最大blur 16、選択時24、ガチャHURのみ48まで。1画面で強い発光は1箇所に限定する。
- ノイズ: 画像素材ではなくCanvasで決定的な微細点を描き、不透明度2〜3%。毎フレーム乱数を更新しない。
- グラデーションは最大3色。すべてのパネルを虹色にしない。

### 3.4 余白、角丸、線、影

- 余白単位: 4 / 8 / 12 / 16 / 24 / 32 / 40 / 56pt
- 画面左右: 16pt。430pt幅以上は20pt。カード全画面表示のみ12ptまで縮小可
- セクション間: 24pt、関連行間: 8〜12pt
- タップ領域: 最小44 x 44pt
- 角丸: チップ6pt、入力12pt、標準パネル18pt、ヒーローパネル24pt、カード20pt
- 主要ボタン: 角丸14ptの角丸長方形。すべてCapsuleにはしない
- 枠線: 1px相当ではなく1ptを基準。選択2pt、カード要素枠3pt、HUR 4pt
- 通常パネル影: 黒35%、radius 12、y 6
- 浮上カード影: 黒45%、radius 18、y 10 + レア色20%、radius 12
- 押下時: scale 0.975、影radiusを40%減らす。移動は最大1pt

### 3.5 アイコン

- 地球マーク、要素記号、王冠、パック、カード裏面はSwiftUI Shape/Canvasで独自に描く。
- SF Symbolsは「戻る」「閉じる」「共有」「音量」「情報」など意味が既に定着した補助操作だけに使う。サイズは原則24pt以下。
- SF Symbolsの地球、箱、稲妻をヒーロー画像として使わない。
- アイコンだけの操作は必ずaccessibilityLabelを付ける。

### 3.6 モーション

| 用途 | 時間 | カーブ |
|---|---:|---|
| 押下 | 0.12秒 | easeOut |
| チップ・タブ選択 | 0.22秒 | easeInOut |
| パネル出現 | 0.28秒 | easeOut、y 8→0 |
| 画面内モード切替 | 0.32秒 | easeInOut、クロスフェード |
| 画面遷移 | 0.38〜0.45秒 | easeInOut |
| 通常カード反転 | 0.72秒 | easeInOut、Y軸 |
| 対戦カード選択 | 0.24秒 | spring response 0.34 / damping 0.82 |
| 勝敗衝突 | 0.65秒 | easeOut |

通常画面の環境アニメーションは8〜14秒の低速1往復とし、画面を見続けないと気づかない程度にする。連続点滅は禁止する。

## 4. 独自コンポーネント体系

実装名は以下へ統一する。類似装飾を各画面へ直書きしない。

### 4.1 土台・ナビゲーション

#### `EarthBackdrop`

- variant: `.archive` / `.home` / `.gacha(tier)` / `.battle` / `.profile`
- 背景グラデーション、地球弧、等高線、静的粒子を描画
- `Reduce Motion` 時は静止画相当の1フレームのみ
- コンテンツのVoiceOver順へ入れない

#### `EarthTopBar`

- 高さ52pt、左右16pt
- leading: 戻るまたは小型地球紋章
- center: 画面名、最大1行
- trailing: 1〜2個の補助操作
- 標準navigation barは非表示にするが、NavigationStack自体は残す

#### `ExpeditionTabBar`

- 5項目: ホーム / 図鑑 / ガチャ / 対戦 / 記録
- 高さ64pt + bottom safe area、上端境界1pt
- 中央ガチャは幅72ptで上へ8ptだけ持ち上げ、地球光輪を付ける
- 選択状態は色だけでなく、上端2ptラインとラベルboldで示す
- タブ再選択で当該タブのルートへ戻る
- VoiceOver順は左から右。各項目44 x 52pt以上

#### `AdDock`

- SDKが返す広告サイズを内包する専用領域。暫定高さ50pt、SDKが60ptを要求する場合は60pt
- 本編開始後、常に `ExpeditionTabBar` の直上へ `safeAreaInset` で確保する
- ガチャ演出中はタブバーを隠すが、CEO決定の常時バナー要件に従いAdDockは残す
- 未読込は高さを維持したまま `ADVERTISEMENT` の小さなラベルと暗い無地背景を表示。偽の広告内容は描かない
- title/onboarding、OS共有シート、StoreKitのシステム購入確認には重ねない

### 4.2 操作

#### `EarthActionButton`

variantと状態を必ず指定する。

| variant | 背景 | 用途 |
|---|---|---|
| `.primary` | earthCyan→stormBlue | 画面の主操作。1画面1個を基本 |
| `.reward` | archiveGold→warningAmber | 報酬獲得、課金購入 |
| `.secondary` | panelRaised + lineQuiet | 補助操作 |
| `.quiet` | 透明 + textSecondary | スキップ、閉じる、詳細 |
| `.danger` | dangerCoral 20% + dangerCoral枠 | 破壊的操作。現状ほぼ使用しない |

- 高さ52pt、角丸14pt、左右16pt
- pressed: scale 0.975、光量60%
- disabled: 彩度0、opacity 0.48。理由を直下に11〜12ptで表示
- loading: ラベル位置を維持し、左に16ptの独自回転リング。多重タップを無効化
- 成功時: 0.35秒だけ境界線をsuccessGreenへ変え、必要ならトーストを出す

#### `ElementSigilButton`

- 要素選択用。最小156 x 104pt、2列
- 固有記号44pt、要素名15pt、補足値12pt
- 背景は要素色8%、左端または上端に要素色3pt
- selected時は枠2pt + 内側光、pressed時はscale 0.98
- ガチャ入口、図鑑要素一覧、課金/ポイントの要素選択で共用する

#### `ArchiveSegmentSwitch`

- 標準Segmented Pickerの代替
- 高さ44pt、2〜3項目まで
- panelBaseの土台上をselected面が0.22秒で移動
- ラベル、選択下線、accessibility valueで状態を示す

### 4.3 情報・フィードバック

#### `ArchivePanel`

- variant: `.standard` / `.raised` / `.hero` / `.warning`
- パディング16pt、角丸18pt（hero 24pt）
- 見出しと本文の間8pt。パネル内をSectionの寄せ集めにしない

#### `ResourceChip`

- 無料回数、ダブりpt、戦績など短い資源値
- 高さ32pt、角丸10pt、アイコン16pt、数字はmonospacedDigit
- タップできる場合のみシェブロンまたは押下状態を付ける

#### `CollectionProgressOrb`

- 直径96pt（compact 80pt）
- 円弧で所持率、中央に `所持数/総数`、下に達成率
- 色だけでなく数値を常時表示。VoiceOverは1要素にまとめる

#### `GameToast`

- 画面上端TopBar直下へ表示。標準alertでなく、軽い結果通知に使う
- success / info / warning / error
- 最大2行、左右16pt、高さ44〜68pt、2.5秒。エラーは自動消去せず閉じる操作を付けてもよい
- ログインボーナス、ポイント不足、購入成功、広告報酬、名前保存に使用
- VoiceOverでは `.accessibilityLiveRegion(.assertive)` 相当の通知を行う

#### `GameModalShell`

- `.sheet` / `.fullScreenCover` の中身へ独自背景、上部グリップ、EarthTopBar、panelを適用
- 標準の白いsheet面を露出しない
- 角丸上端24pt、背景earthAbyss、medium/large detent
- カード詳細、要素選択、名前編集、確率表示に使用
- OS共有シートとStoreKit確認は対象外

#### `GameEmptyState`

- 独自紋章64pt、タイトル17pt、説明13pt、必要なら1つのCTA
- Game Center未認証、ランキング0件、国旗未取得、豆知識準備中へ使用

### 4.4 カード

#### `CollectibleCardView`

現行 `CardView` の置換先。業務ロジックから独立し、次の入力だけを持つ。

- `card`, `country`
- reveal: `.hidden` / `.valueHidden` / `.revealed`
- size: `.mini(72 x 100)` / `.battle(104 x 146)` / `.grid(156 x 218)` / `.hero(226 x 316)` / `.share(360 x 504)`
- emphasis: `.normal` / `.selected` / `.winner` / `.new`
- animationPolicy: `.live` / `.static`。共有画像は必ずstatic

カードの縦横比は0.714に統一し、`scaleEffect` だけでサイズ変更しない。サイズごとにframeと文字スケールを計算する。

面の順序:

1. レア度別の素材面（単色ではなく、レア別の線・格子・金属模様）
2. 上段: レア度、要素記号、データ年
3. 国旗領域: 全幅、比率3:2。読込失敗時は国コード+等高線
4. 国名: 1行
5. 要素名
6. 数値+単位: 最重要。1行、minimumScaleFactor 0.55
7. 下端: 世界順位またはスコアを表示する場合の小領域
8. 外枠: 要素色を濃淡なしで3pt

レア度バッジは色だけでなく枠形を変える。SSR以上の常時エフェクトは毎秒点滅させず、6〜10秒に1回の光沢移動だけにする。HURの未入手表示では国旗・国・要素を一切出さず、黒いカード面、地球の欠けた紋章、`UNKNOWN` のみ表示する。

#### `CardBackView`

- 承認済みデモの黒地、地球輪郭、ティア色の細枠を基準
- どのカードかを裏面色で漏らさない。カード個別レア度は反転開始後の光で初めて分かる
- HURをめくる前にも裏面からHUR確定と分かる演出は入れない。ただし導入は回の最高レア度でHUR演出になる仕様なので、回全体としての示唆は許容

#### `CardDetailOverlay`

- 標準sheet風の白面を廃止し、暗い観測台の上にheroカードを置く
- 上部に閉じる、中央にカード、下にスコア・データ年・シェアCTA
- heroカードのframeを実寸で確保。`scaleEffect`による既知の文字重なりを再発させない
- シェア画像は `CollectibleCardView(size: .share, animationPolicy: .static)` を3倍相当で描画し、目標1080 x 1512px

## 5. 画面別変更仕様

### 5.1 タイトル・起動

構成は上からではなく全画面レイヤーで作る。

- 背景: 承認済みデモの `StaticEarthBackdrop` をブランド用に調整。画面下46%から地球弧、上部に静かな雲、雨粒は最大24本
- 中央: 独自地球紋章90pt、`Country Cards Collection` 30pt、サブタイトル13pt
- 下部: 「タップしてはじめる」ではなく、幅240pt・高さ52ptの光の境界。タップ領域は画面全体を維持
- 1.8秒後から地球の縁が10秒周期で呼吸する。連続点滅なし
- タップ時: 光が中心へ0.22秒収束し、0.38秒クロスフェードでホームへ
- Reduce Motion: 静止背景、タップ時は0.15秒フェードのみ
- 初回で名前未登録の場合は、タイトル後に名前登録へ進み、その完了後ホームへ。図鑑へ直接入らない

完了条件:

- SF Symbolsの地球を主役に使っていない
- 起動直後150ms以内に背景とタイトルの静止状態が見える。Canvas初期化待ちで白画面を出さない
- 画面全体タップ、VoiceOverの「はじめる」操作、既存IDが動く

### 5.2 初回名前登録

- タイトルと同じ背景を暗くし、中央に `ArchivePanel(.hero)`
- 見出し「探査記録を作成」、説明「ランキングに表示する名前を決めてください」
- 入力は高さ52pt、角丸12pt。標準roundedBorderを外し、panelRaised背景+earthCyanのfocus枠2pt
- 残り文字数 `0/12` を右下に表示。12文字超過は現行どおり切り詰める
- CTA「世界の記録をはじめる」
- 空白のみ、空欄はdisabled。理由「1文字以上入力してください」を表示
- キーボード表示時もCTAが隠れないようsafeAreaInsetまたはscrollDismissesKeyboardを使う

完了条件:

- 初回のみ閉じられず、保存後ホームへ進む
- 日本語12文字、英数12文字、前後空白、空欄を確認
- 標準fullScreenCoverの白背景が見えない

### 5.3 ホーム（新しいアプリ内ルート）

既存の機能への入口と進捗を集約するUI上のハブを追加する。新しい報酬・保存データ・ミッションは追加しない。

上から次の順に配置する。

1. `EarthTopBar`: 左に地球紋章、中央に「EARTH ARCHIVE」、右にユーザー名/王冠
2. 資源行: 無料ガチャ残数、ダブりptを `ResourceChip` で表示
3. ヒーローパネル: `CollectionProgressOrb` と「世界の記録 所持数/総数」。タップで図鑑へ
4. 主CTA: 「カードを観測する」=ガチャへ。残数0ならラベルを「入手方法を見る」とし、ガチャの枯渇画面へ
5. 2分割パネル: 「CPUと対戦」「全国ランキング」
6. 今日の状態: 広告残数、対戦報酬残数、ログイン受取済みを横3項目。既存値のみ表示
7. `AdDock`
8. `ExpeditionTabBar`

縦が667pt以下では、ヒーローOrbを80pt、パネル間隔12ptに縮め、内容をScrollView化する。主CTAとTabBarは常に操作可能にする。

完了条件:

- タイトル通過後の最初の画面がホーム
- 既存4領域と確率/ランキング/課金への到達手数が増えない
- 表示する残数・所持数が各Managerと一致する
- ホーム追加のために新しい保存データを作っていない

### 5.4 ガチャトップ・要素選択

- TopBar「カード観測」、右に「排出確率」アイコン+文字
- 上部に無料残数のhero resource panel。残数3以上はcyan、1はamber、0はcoral境界
- 広告報酬はhero panel内のsecondary action。残り回数をラベルに含める
- ポイント、¥100は「別の観測方法」として2枚の横長パネルに常時表示し、標準Menuへ隠さない
- 10要素は `ElementSigilButton` の2列グリッド。箱アイコンは廃止する
- 各要素パネルに `要素名 / 所持数・総数 / 固有記号` を表示。カード総数の算出は既存databaseを使う
- ログインボーナスは標準alertでなく `GameToast(.success)`。「無料ガチャ +N回」を表示
- 枯渇時は専用warning panelに、広告CTA（残数>0のみ）、ポイントCTA、¥100 CTAを置く。課金だけを過度に強調しない

完了条件:

- 10要素すべてがスクロールで選べ、各アクセシビリティIDが維持される
- 排出確率、ポイント、課金が標準Menuを開かず到達できる
- 無料0、広告残0、商品未読込の組合せで不正なCTAが出ない

### 5.5 ガチャ導入・パック開封・カード公開

詳細は「6. 承認済みガチャデモの統合仕様」を正とする。

画面上の常設UI:

- 左上: 戻る。抽選済みカード未受取を防ぐため、intro開始後は確認なしで閉じさせず、戻る操作は結果受取後または既存受取保証を実装した場合のみ有効化
- 右上: 「スキップ」。introPausedから表示し、カード公開へ入った後は非表示
- 下端: AdDock。演出の中心、パック、カードと重ならない
- ナビゲーションタイトルとタブバーは演出中非表示

通常モード:

1. 抽選完了後、回の最高レア度に対応する停止画を表示
2. ユーザーがタップするまで動かない
3. タップで導入→衝撃→パック開封を再生
4. カード裏面へ切り替え、再びタップ待ち
5. 1回のタップで1枚を反転し、もう1回で次の裏面へ
6. 全枚数後に結果画面

スキップモード:

1. introPausedまたは再生中にスキップ可能
2. 即座にカード裏面へ
3. N/SRは0.60秒間隔で自動公開・自動進行
4. SSR/UR/HURは必ず停止し、ユーザータップを待つ
5. 各カードの受取処理は現行どおり公開時に一度だけ行う

完了条件:

- 導入ティアは回の最高レア度、反転光はめくったカード自身のレア度
- N/SRの反転閃光なし、SSR紫白、UR金白、HUR金白青の最上位演出
- スキップと通常のどちらでも最終的な受取枚数・New判定・ポイントが同じ
- 多重タップ、画面離脱、バックグラウンド復帰で重複受取しない

### 5.6 ガチャ結果

- 見出しは「観測完了」。最高レア度色の細い上光を置く
- 3枚は縦羅列ではなく、最上位カードをhero、残り2枚をmini〜gridで配置。すべて同レアなら取得順をheroにする
- 各カードへ `NEW` または `DUPLICATE +1pt` の状態バッジ。現行 `isNewByIndex` と受取結果から表示する
- カードタップで `CardDetailOverlay`、共有は詳細内と各カードの補助操作から可能
- 下部に主CTA「もう一度観測」、secondary「ガチャ選択へ」
- 無料0の場合は主CTAを押せないまま残さず、広告/ポイント/¥100の枯渇パネルへ置換
- 10/100回のまとめ引きは同じ世界観の結果グリッドを使い、レア度フィルタと `NEWのみ` 切替をUIローカル状態として許可する。抽選・受取ロジックは変えない

完了条件:

- 3、30、300枚でスクロールが破綻しない
- HUR、UR、SSR、N/SRの混在でも個別状態が正しい
- 共有画像に動画・透明不足・切れがない

### 5.7 図鑑・コレクション

トップ:

- TopBar「世界の記録」
- 所持進捗Orb、国数、総カード数をhero panelへ
- `ArchiveSegmentSwitch` で「国から探す / 要素から探す」
- 検索は国別にのみ表示。独自背景の検索fieldを使い、標準search barを全面露出させない
- 対象範囲の注意は常時長文で先頭を占有せず、「国連加盟193カ国」情報パネルから詳細を開く。内容は削除しない

国一覧:

- ListをScrollView+LazyVStackへ置換
- 行高さ68pt、旗48 x 32pt、国名、所持数、横進捗バー、右端に独自シェブロン
- コンプリート国はgold境界と「COMPLETE」。未所持0の国も行自体は同じ高さ

要素一覧:

- `ElementSigilButton` 2列。所持数/存在数、達成率を表示
- 色付きCircleだけで区別しない

国詳細:

- 上部に国旗、国名、`所持/存在`、円形進捗
- 存在する9または10枚をグリッド表示。未入手はカードシルエット
- HURは通常グリッド外の「未確認記録」専用台座へ単独表示し、未入手時は内容を伏せる
- 豆知識は「観測ログ」タイムライン。解放済みは番号+本文、未解放は鍵+必要枚数
- 9枚国の10件解放式は既存ロジックをそのまま使う

完了条件:

- 193カ国、10要素、データ欠損カード数が現行databaseと一致
- 未所持カードから詳細を開けず、所持カードから開ける
- モナコ等9枚国で9枚所持時に豆知識10/10
- 320pt相当の狭幅でも2列カードが切れない。難しければ1列へ切替

### 5.8 カード詳細

- `GameModalShell` のlarge detentを初期値にし、heroカード全体を一度に見せる
- 上段に閉じる、レア度、New/所持済み
- 中段にheroカード。左右余白16pt以上
- 下段にスコア、データ年、出典への導線、共有CTA
- HURは「データ非公開」を事実ベースで表示し、煽り文言を追加しない
- 共有CTAの押下後のみ標準共有シートを開く

完了条件:

- 既知バグであるカード外枠とスコア文字の接触が全端末でない
- 長い国名、長いCO2単位、Dynamic Typeで切れない
- 共有画像がカード表示と同じレア・要素・数値を持つ

### 5.9 全国ランキング

- `ArchiveSegmentSwitch` で所持枚数 / 対戦勝利 / ガチャ回数
- 上位3名は表彰台ではなく「軌道リング」3枚のhero row。1位中央または先頭をgold、2位cyan、3位copper
- 4位以下は高さ58ptの独自行。順位、プレイヤー名、値
- 自分のentryが取得できる場合は画面下へ固定した `YOUR RECORD` panel。現行APIで取れない場合は追加のサーバーを導入せず非表示
- 所持コンプリートの「コンプリート(達成日)」表示と早期達成順を維持
- 未認証、loading、0件、通信エラーを `GameEmptyState` / skeletonで分離

完了条件:

- 3Leaderboardの切替で表示単位が正しい
- Game Center未認証でもクラッシュせず、設定方法が分かる
- 長いGame Center名が1行で縮小または末尾省略され、値を押し出さない

### 5.10 対戦ホーム

- 背景は地球の昼夜境界を上下に割ったbattle variant
- hero panelに「WORLD CLASH」、5ターン、CPU対戦、報酬残数
- ルールは3つの短いステップへ分割: CPUを見る / 4枚から選ぶ / 高低で決着
- 主CTA「対戦を開始」高さ56pt
- 今日の勝利報酬残数をResourceChipで表示
- 長い説明文を1つのcaptionで置かない。詳細ルールはsecondary panelからモーダル表示

完了条件:

- デッキ編成導線を復活させない
- 初見で「数値は選ぶまで見えない」「高低は毎回変わる」「5要素が重複しない」が読める

### 5.11 対戦中

常に上から `ターン/戦績`、`お題+高低ルール`、CPUカード、衝突線、自分の4枚の順。

- Top status: `TURN 1/5` と `あなた 0 — 0 CPU`
- ルールバナー: 高い方=`stormBlue`+上矢印、低い方=`warningAmber`+下矢印。高さ52pt、20pt bold
- CPUカード: 104 x 146pt（通常）、SEは92 x 129pt。国・要素表示、数値は `???`
- プレイヤー候補: 2列、通常104 x 146pt、SEは92 x 129pt。カード間8〜12pt
- 選択時: 選択カードが0.24秒で中央へ12pt浮上、他3枚opacity 0.45。入力をロック
- 決着: 選択カードとCPUカードが中央へ寄り、0.65秒の大気衝突。絵文字⚡️は使わず、Canvasの線・火花・円形衝撃波
- 決着後: 両者の数値を同時公開。勝者にwinner枠、同値は両方にDRAW枠
- 選ばなかった3枚はminiカード横並びで数値公開し、見出しは決定済みの「選ばなかった手札」
- 「次へ」は結果が読み終わる位置に固定せず、画面下safe areaの上へsticky配置してもよい。ただしminiカードを隠さない

完了条件:

- CPU先出し、4択、同時公開、選ばなかった3枚公開、5要素重複なし、同値引き分けが維持される
- SEで候補4枚を選択可能。スクロールが必要でもルールとCPU国名を見失わない
- 多重タップで複数カードを選べない
- VoiceOverでは候補カードごとに国・要素・「数値は未公開」を読み、選択後に勝敗と両数値を通知

### 5.12 対戦結果

- 画面全体を別phaseとして表示。勝利=夜明けのcyan/gold、敗北=雨のdeep blue、引分=静かな白青
- 見出し、最終戦績、5ターンの小さな結果ドット（勝/負/分）、報酬panel
- 勝利かつ報酬対象: `無料ガチャ +1回` をgold panelで表示
- 上限済み: 「本日の対戦報酬は受取済み」をquiet panelで表示
- CTA: 主「もう一度対戦」、副「ホームへ」。再戦は既存ViewModelを新規生成または明示resetし、前試合状態を持ち越さない
- 敗北時に課金・広告を差し込まない

完了条件:

- 勝/負/分の3状態と報酬有/無の組合せを表示
- 累計勝数、無料回数、Game Center同期が現行どおり一度だけ更新

### 5.13 記録・プロフィール

タブ名は「プロフィール」ではなく「記録」、画面タイトルは「探査記録」とする。保存データは変えない。

- 上部hero: 王冠を独自shapeで大きく表示、ユーザー名、所持数、次の王冠までの進捗
- 記録3枚: 対戦累計勝利、ガチャ累計回数、ダブりpt
- CTA panel: 全国ランキング
- 設定アイコンから設定画面へ
- 王冠説明は常時長文Sectionでなく、王冠タップ時のモーダルへ
- 名前編集は標準alertでなく `GameModalShell` 内の入力パネル

完了条件:

- CrownTierの10段階計算を変えない
- 数値へiOSの意図しないカンマが付かない
- 名前編集12文字制限が初回登録と同じ

### 5.14 設定・このアプリについて

新しい業務設定は増やさず、現行情報を次のグループへ再配置する。

- アカウント: プレイヤー名、Game Center状態
- データ: 対象「国連加盟193カ国」、存在しない組合せ、生成日、世界銀行更新日
- 出典: 世界銀行、Wikidata、countries.dev、flagcdn.com
- 表示: 「動きを減らす」はアプリ独自toggleを作らず、端末設定に連動している旨と設定アプリへの説明を表示
- アプリ情報: 正式名称、バージョン（取得可能ならBundleから）

標準List/Sectionではなく `ArchivePanel` の縦並びにする。外部リンクが実在しない項目はタップ可能に見せない。

完了条件:

- 現行 `AboutView` の情報が欠落しない
- 出典と対象範囲が2タップ以内で読める
- Game Center未認証状態が明示される

### 5.15 課金・ポイント・広告

#### ポイント

- 最上部に保有pt。1回/10回/100回を商品カード3枚として表示
- 各商品に必要pt、受取枚数3/30/300、最終保証を明記
- 購入可能な商品だけ強く光らせる。disabled理由に不足ptを表示
- 抽選後は無料ガチャと同じCinematic/Reveal/Resultパイプラインを使う

#### ¥100課金

- 要素選択後、1商品だけの `PurchasePanel`
- 表示順: 商品名、価格、30枚、30枚目SSR以上、排出確率リンク、購入CTA
- 排出確率リンクはCTAより前に置く。実際のStoreKit価格を正とし、固定文字列だけに依存しない
- 読込中はskeleton、失敗はerror panel+再読込
- 購入中はCTA loading、多重購入無効。成功後のみガチャ演出へ
- 消耗型商品のため、根拠なく「購入を復元」を追加しない

#### 排出確率

- 標準Listをやめ、レア度ごとの横棒+数値で表示
- HUR `1/20,000,000` は独立warningではなくspecial archive panel。煽らず事実を表示
- `source` ごとに保証内容を正しく出し分ける現行実装を維持
- 率の合計と保証対象枚数を画面上で読み違えない章立てにする

#### 広告

- バナーは `AdDock`、リワード広告は `RewardAdPanel`
- CTA文言に報酬 `無料ガチャ +1回` と本日残数を明記
- loading / 再生中 / 報酬付与 / 上限 / 失敗の5状態を持つ
- 広告SDK未組込の現段階で「視聴したように見せる」完成UIにはしない。開発ビルドでは `広告SDK未接続` を小さく明示
- 広告失敗時は回数を消費せず、error toastと再試行を表示

完了条件:

- IAP購入前に正しい確率・保証が見える
- ポイント10連と課金10連の保証差を混同しない
- 広告上限到達時に報酬CTAが出ない
- 購入・広告エラーでアプリが進行不能にならない

## 6. 承認済みガチャデモの本体統合仕様

### 6.1 移植元と移植しないもの

移植元は `prototypes/CountryCardsGachaDemo/CountryCardsGachaDemo/GachaDemoView.swift`。

再利用する考え方・描画:

- `StaticEarthBackdrop`
- `EarthStormScene`
- `PhenomenonBurst`
- `PackOpening`
- `RadianceLayer`
- `EclipseLayer`
- `CardTurnFlash`
- gathering → impact → pack → cards の内部進行
- `runID` またはcancel可能Taskで古い非同期処理を無効化する方式

本体へ持ち込まないもの:

- デモ選択画面、`DemoTier` のUI
- `DemoCard` の架空国・英語カード
- `FinaleView` の「レア度選択へ戻る」
- デモの自動開始。本体は `introPaused` で必ずタップ待ち
- デモ独自の3枚固定配列

### 6.2 型の対応

`DemoTier` をそのままアプリModelへ入れず、UI層に `GachaVisualTier` を作る。

| 実データ | 導入 `GachaVisualTier` | 導入の主表現 |
|---|---|---|
| 最高がNまたはSR | normal | 夜明け前の雨、cyanの弱い地球縁 |
| 最高がSSR | ssr | 青い暴風雨、白青の稲妻 |
| 最高がUR | ur | 紫金のスーパーセル、地球光の収束 |
| 最高がHUR | hur | 無音感の皆既食、金白青の極光、最長の余韻 |

導入値は `pullResult.cards.map(\.rarity).max()`、すなわち既存 `highestRarity` だけから決める。並び順や1枚目のレア度から決めない。

反転光は次の通り、公開対象 `cards[index].rarity` から毎回決める。

| 個別カード | 反転光 | 光時間 | 入力ロック |
|---|---|---:|---:|
| N | なし | 0秒 | 通常反転0.72秒の間 |
| SR | なし | 0秒 | 通常反転0.72秒の間 |
| SSR | 紫→白、1リング | 0.55秒 | 0.75秒 |
| UR | 金→白、3リング、14粒 | 0.95秒 | 1.00秒 |
| HUR | 金→白→cyan、5リング、24粒、食の残像 | 1.25秒 | 1.30秒 |

**禁止**: 回の最高がURだから3枚全部を金白発光にする実装。最高レア度は導入だけ、個別レア度は反転だけに使う。

### 6.3 時間

Reduce Motionがoff:

| 段階 | normal/SSR/UR | HUR |
|---|---:|---:|
| introPaused | 無期限 | 無期限 |
| gathering | 2.20秒 | 2.90秒 |
| impact | 1.05秒 | 1.60秒 |
| pack | 2.65秒 | 2.65秒 |
| cards待機 | ユーザー操作 | ユーザー操作 |

Reduce Motionがon:

- gathering 0.60秒のクロスフェード
- impact 0.40秒の色面切替。全面白フラッシュは禁止
- pack 0.70秒で閉→開の2状態をフェード
- カード反転は0.15秒クロスフェード。レア発光は静止haloを0.35秒表示

### 6.4 ViewModelとの接続

現行の `GachaPlayViewModel` は `introPlaying` に入った後、固定1.2秒でrevealingへ進む。デモの実時間とは一致しないため、実装時は次の責務分離にする。

- ViewModel: 抽選、無料回数消費、phase、受取、New、skip規則だけを持つ
- `GachaCinematicView`: gathering/impact/packという表示内部phaseと時間を持つ
- Cinematic終了時に `viewModel.finishIntro()` を1回だけ呼ぶ
- skip時にCinematic Taskをcancelし、`viewModel.tapSkip()` を1回だけ呼ぶ
- Viewが消えた時はTaskをcancel。再表示で古いTaskがphaseを進めない

`finishIntro()` は `phase == .introPlaying` の時だけ `.revealing(index: 0, faceUp: false)` へ進む冪等な処理にする。抽選ロジックや受取処理をCinematicへ入れない。

### 6.5 まとめ引きへの適用

現在ポイント/IAPは結果一覧へ直接進むが、CEO決定の「回数によらず通常/スキップモード」と世界観統一のため、30/300枚も同じ表示パイプラインへ接続する。

- 導入はバッチ全体の最高レア度で1回だけ再生
- カード公開は取得順
- 通常モードは1枚ずつタップ
- スキップモードはN/SR自動、SSR以上停止
- 結果はvirtualized grid。300個のCardViewを一度にアニメーションさせない
- 無料3枚は現行どおりカード公開時に `receive` する。ポイント/IAPは現行どおり抽選直後（IAPは購入成功後）に全枚数を `receive` 済みにする
- ポイント/IAPの演出は「受取処理」ではなく「受取済みカードの閲覧状態」だけを進め、反転時に `receive` を再実行しない。これにより画面離脱でも購入済みカードが消えず、ダブりポイントも二重加算されない
- ポイント/IAPでもNew/duplicateを表示する場合は、既存の `receive` 戻り値を抽選時に配列へ保存するだけとし、判定を演出側で再計算しない

### 6.6 描画性能上の修正

デモではTimelineViewが入れ子になる箇所がある。本体移植では1画面につき時間源を1つにする。

- 親 `TimelineView` からelapsedを子へ渡す
- 通常24〜30fps、反転中のみ必要なら60fps
- rain粒子上限: normal 45、SSR 63、UR 81、HUR 99
- HUR光線10、反転粒子24を上限
- `scenePhase != .active` でTimelineとTaskを停止
- 毎フレームUUID、配列、乱数、DateFormatterを作らない

## 7. SwiftUI実装構造

推奨ディレクトリ。既存Model/Servicesは移動しない。

```text
CountryCards/
  App/
    CountryCardsApp.swift
    AppShellView.swift
  DesignSystem/
    Theme/
      EarthTheme.swift
      ColorTokens.swift
      TypographyTokens.swift
      LayoutTokens.swift
      MotionTokens.swift
    Backgrounds/
      EarthBackdrop.swift
      TopographyCanvas.swift
    Components/
      EarthTopBar.swift
      ExpeditionTabBar.swift
      EarthActionButton.swift
      ArchivePanel.swift
      ArchiveSegmentSwitch.swift
      ResourceChip.swift
      GameToast.swift
      GameModalShell.swift
      GameEmptyState.swift
      ElementSigil.swift
      AdDock.swift
    Cards/
      CollectibleCardView.swift
      CardBackView.swift
      CardRarityEffects.swift
      CardDetailOverlay.swift
    Effects/
      GachaCinematicView.swift
      EarthStormScene.swift
      PackOpening.swift
      CardTurnFlash.swift
      BattleImpactEffect.swift
  Screens/
    Home/
    Collection/
    Gacha/
    Battle/
    Profile/
    Settings/
```

既存ファイルを一度に移動する必要はない。最初はDesignSystemを追加し、各現行Viewを中身から置換する。全画面完了後にScreenへ整理する。

### 7.1 依存方向

```text
Screens → DesignSystem → SwiftUI
Screens → ViewModels / Models / Services
DesignSystem → Card / Country / Rarity / CardElement（表示に必要な最小型のみ）
Models / ViewModels / Services ↛ DesignSystem
```

表示都合の色やFontを `Rarity` / `CardElement` のModelへ増やし続けない。現在の `baseColor` / `borderColor` は移行期間中の互換として残し、最終的にはDesignSystem側の `RarityVisualStyle` / `ElementVisualStyle` で解決する。確率・Comparable等のModel責務は不変。

### 7.2 状態の所有

- 画面遷移・選択タブ: `AppShellView`
- 業務状態: 既存Manager/ViewModel
- 一時的な表示（segment、toast、sheet、カード選択強調）: 各Screen
- 反復アニメーション: 専用Effect View
- 抽選や保存を `onAppear` の装飾Viewから呼ばない

## 8. 既存ロジックを壊さない移行順

### Phase 0: 回帰基準固定（P0）

- 既存UIテスト6本以上を変更前に通す
- 無料回数、3枚目保証、skip停止、4択対戦、9枚国豆知識、タイトルを基準化
- 主要画面のスクリーンショットをSE/標準/Pro Maxで保存
- コード変更前に現在の `OwnedCollection` 保存キー一覧を記録

### Phase 1: DesignSystem土台（P0）

- tokens、EarthBackdrop、ArchivePanel、Button、TopBar、Toastを追加
- 既存画面へまだ全面適用せず、Preview/専用fixtureで状態を確認
- ライト/ダークOS設定の両方でアプリ既定ダーク外観を確認

### Phase 2: カード統一（P0）

- `CollectibleCardView` を全サイズで作る
- 現行 `CardView` の3状態 `isRevealed/hideValue` を完全対応
- 国詳細、ガチャ、対戦、共有の順で差し替える
- `scaleEffect` サイズ調整を除去し、frameベースへ

### Phase 3: ガチャデモ統合（P0）

- デモ描画をEffectsへ移植
- ViewModelに冪等なintro完了フックを追加
- 無料3枚で通常/skip/4ティア/Reduce Motionを確認
- 次にポイント・IAPまとめ引きを同じpipelineへ接続

### Phase 4: AppShell・タイトル・ホーム（P0）

- 5タブのAppShell、AdDock、Homeを導入
- タイトル→名前登録→ホームの順を確定
- 既存4領域へのnavigation destinationを維持

### Phase 5: 図鑑・詳細（P1）

- 標準List/segment/sheet外観を置換
- 国193件のLazyVStack性能、9枚国、HUR秘匿、共有を確認

### Phase 6: 対戦（P1）

- BattleHome、選択、衝突、ラウンド結果、試合結果を置換
- BattleViewModelの判定には触れず、phaseごとの表示を差し替える

### Phase 7: 記録・ランキング・設定（P1）

- Profile/List/alert/About/Leaderboardを独自panelへ
- Game Center状態4種を確認

### Phase 8: ポイント・課金・広告（P0審査項目を含む）

- 確率表示と保証差を先に固定
- StoreKitの実価格、loading/error/success
- 広告SDK接続後にAdDockとRewardAdPanelの状態を結線

### Phase 9: 最適化・全体チェック（P0）

- Reduce Motion、VoiceOver、Dynamic Type、端末3サイズ
- InstrumentsまたはXcode計測でCPU/メモリ/フレーム落ちを確認
- 作成担当とは別のチェック担当が本書のチェックリストで指摘のみ実施

## 9. アクセシビリティ

### 9.1 必須要件

- 通常文字4.5:1、大文字・18pt以上3:1、操作境界3:1以上
- タップ領域44 x 44pt以上
- Dynamic Type: 本文・ボタン・見出しは少なくともAX2まで。カードは形を維持し、VoiceOverと詳細画面で完全な値を提供
- 色だけで選択、勝敗、レア度、要素を示さない
- VoiceOver順を視覚順に合わせる。装飾Canvasはhidden
- カード1枚は複数断片ではなく1要素にまとめ、例「SSR、日本、人口、1億2400万人、2025年のデータ」
- 数値非公開は「はてな」だけでなく「数値は未公開」と読む
- 勝敗確定時に「あなたの勝ち。日本1億2400万人、CPU…」を通知
- エラー/報酬トーストは読み上げる
- キーボード、Switch Control、Voice Controlで主要フローを完走できる

### 9.2 Reduce Motion

`@Environment(\.accessibilityReduceMotion)` をTheme/Effectへ渡し、各画面独自判断にしない。

- 背景雨・雲・光輪のループ停止
- 3D反転→0.15秒クロスフェード
- 移動を伴う画面遷移→opacityのみ
- 雷の白フラッシュ→静かな境界光
- 自動進行の待ち時間は必要最小限へ短縮するが、抽選・受取順は変えない
- HURの格差は色、枠数、静止haloで維持

### 9.3 Reduce Transparency / Increase Contrast

- `accessibilityReduceTransparency` 時はpanelを100%不透明にし、blurを使わない
- Increase Contrast相当ではlineQuietを70%以上、secondary textを明るくする
- Smart Invertで国旗を反転させない設定を検討する

## 10. 端末サイズ・レイアウト

検証対象:

- compact: iPhone SE (第3世代) 375 x 667pt
- standard: 393 x 852pt
- large: 430 x 932pt
- 追加: 320pt幅相当のPreviewで文字切れ確認

ブレークポイント:

- 幅390pt未満: 左右余白12〜16、hero Orb 80、対戦カード92 x 129、カード詳細hero最大206 x 288
- 幅390〜419pt: 基準値
- 幅420pt以上: 左右20、カードgrid 164 x 230まで拡大可。本文の最大幅398pt
- 高さ700pt未満: ヘッダー間隔・hero高さを20%縮小し、ScrollViewを許可。CTAを内容へ重ねない

Safe Area:

- Dynamic Island/ノッチ上へ文字を置かない
- Bottom tab + AdDock + home indicatorの合計高を中央コンテンツから差し引く
- キーボード表示時、オンボーディングと名前編集のCTAが見える

## 11. パフォーマンス基準

- 対象基準端末: A15相当で通常画面60fps、ガチャCanvasは最低30fpsを維持
- 通常画面のCPU負荷をアイドル時平均8%未満目標、ガチャ再生中35%未満目標（Debug値は参考、Releaseで確認）
- ガチャUI追加によるピークメモリ増分32MB以内を目標
- 画面に存在するTimelineViewは1つ。非表示タブのアニメーションを停止
- LazyVStack/LazyVGridを使い、193行・300カードを一括生成しない
- 国旗は同一URLの再取得を抑えるcache層または既存URLCacheを確認する。取得失敗でもplaceholderでレイアウトを維持
- shadow+blur+blendModeを同じ要素へ3層以上重ねるのはガチャHURだけ
- TaskをView消失時・skip時・再実行時にcancel。`runID` 方式を使う場合は全phaseでguardする
- 毎フレームの乱数生成を避け、粒子位置はseeded配列として事前生成
- `GeometryReader + .animation(value:) + .id()` による差し替えを避け、サイズ固定と手動opacityで遷移する

## 12. 状態マトリクス

主要コンポーネントは最低限以下をPreview/テストfixtureで持つ。

| 対象 | 必須状態 |
|---|---|
| Button | normal / pressed / disabled / loading / success |
| Resource | normal / low / zero / justGranted |
| Card | hidden / valueHidden / revealed / selected / winner / new / duplicate / HUR |
| Flag | loading / loaded / failed / offline |
| Gacha | introPaused / gathering / impact / pack / cardBack / flipping / faceUp / done / skipped |
| Purchase | loading product / purchasable / purchasing / success / cancelled / failed |
| Reward ad | available / loading / playing / rewarded / exhausted / failed |
| Battle | choosing / selectionLocked / revealing / playerWin / cpuWin / draw / finished |
| Ranking | unauthenticated / loading / entries / empty / error |
| Trivia | unlocked / locked / preparing / allUnlocked9CardCountry |

## 13. 画面ごとの検証チェックリスト

### 起動・ホーム

- [ ] 白画面を挟まずタイトル静止画が出る
- [ ] タップ前にガチャ映像が勝手に動かない
- [ ] 初回は名前登録、2回目以降はホームへ進む
- [ ] ホームから図鑑・ガチャ・対戦・ランキング・記録へ到達できる
- [ ] 無料残数、広告残数、ポイント、所持数が実値と一致する
- [ ] バナー広告領域とタブ/ホームインジケータが重ならない

### 図鑑

- [ ] 国/要素切替が標準segmented外観でない
- [ ] 193カ国と10要素が表示される
- [ ] 欠損カードの分母が正しい
- [ ] 未所持・所持・completeを色以外でも識別できる
- [ ] HUR未所持時に国・要素の中身を伏せる
- [ ] モナコ9枚所持で豆知識10/10
- [ ] 長い国名と単位が切れない

### ガチャ

- [ ] 10要素入口、無料、広告、ポイント、¥100が正しい状態で表示される
- [ ] 回の最高N/SR→normal、SSR→SSR、UR→UR、HUR→HURの導入になる
- [ ] タップ前に導入が停止している
- [ ] normal/SSR/URは5.90秒、HURは7.15秒を基準にカード待機へ進む
- [ ] N/SRのカード反転に発光なし
- [ ] SSRは紫白0.55秒、URは金白0.95秒、HURは金白青1.25秒
- [ ] skipでN/SRは自動、SSR以上は停止
- [ ] 通常/skip/Reduce Motionで受取・New・duplicate pointが一致
- [ ] 3/30/300枚で欠落・二重受取がない
- [ ] 全phaseで戻る、バックグラウンド、再表示、多重タップを試す

### 課金・広告・確率

- [ ] 課金CTAの前に排出確率がある
- [ ] 課金10連=30枚目SSR以上、ポイント10連=30枚目SR以上、ポイント100連=300枚目SSR以上
- [ ] HUR確率は `1/20,000,000`
- [ ] StoreKit商品未読込、キャンセル、失敗、成功を表示できる
- [ ] 広告失敗で残数を消費しない
- [ ] 広告上限時にreward CTAを隠すまたは明確にdisabled
- [ ] バナーは本編の各画面で専用領域に収まる

### 対戦

- [ ] CPU国・要素を先に見せ、数値は隠す
- [ ] 自分の4候補すべての数値を隠す
- [ ] 高い/低い勝利条件が常に大きく見える
- [ ] 1枚だけ選択でき、決着後に両数値が同時公開される
- [ ] 選ばなかった3枚の数値も公開される
- [ ] 同値はターン引分、試合引分も許容
- [ ] 5ターンで要素重複なし
- [ ] CPUにHURが出ない
- [ ] 勝利報酬は1日上限に従い一度だけ付与

### 記録・ランキング・設定

- [ ] 王冠段階、所持数、累計勝利、累計ガチャ、ポイントが一致
- [ ] 名前変更は12文字、空欄不可
- [ ] 3ランキングの単位とcomplete日付表示が正しい
- [ ] Game Center未認証・0件・エラーを区別する
- [ ] 国連加盟193カ国、欠損カード、全データ出典、更新日、生成日が読める

### アクセシビリティ・端末・性能

- [ ] VoiceOverでタイトル→ガチャ→結果、タイトル→対戦→結果を完走
- [ ] 色をグレースケールにしてもレア度・要素・勝敗が分かる
- [ ] Dynamic Type AX2で主要CTAが切れない
- [ ] Reduce Motionでループ、3D反転、全面フラッシュが止まる
- [ ] Reduce Transparencyで本文背景が不透明になる
- [ ] SE/393pt/Pro Max/320pt Previewで重なりなし
- [ ] ガチャ中30fps以上、通常画面でスクロールの目立つ引っかかりなし
- [ ] 背景化・skip・画面離脱後にTask/Timelineが残らない

## 14. 自動テスト・視覚テストの追加指針

既存テストを置き換えず、次を追加する。

- `GachaVisualTierTests`: highestRarityの4分類
- `CardFlashStyleTests`: N/SR none、SSR violetWhite、UR goldWhite、HUR hyper
- `GachaCinematicStateTests`: paused→playing→finished、skip、cancel、二重finish
- `GachaReceiptConsistencyTests`: 通常/skipでreceive回数一致
- `ThemeContrastTests`: tokenの主要組合せが基準値以上
- `HomeNavigationUITests`: 5入口
- `PurchaseDisclosureUITests`: source別保証文言
- `ReduceMotionUITests`: 起動引数または環境で短縮経路
- スクリーンショットfixture: Title、Home、Collection、Gacha tier 4種、Card rarity 5種、Battle 3結果、Profile、Leaderboard 4状態

スクリーンショットは作成担当の自己確認に使った後、別チェック担当が本書のみを基準に指摘する。差分画像だけで合否を決めず、文字切れと操作可能性も確認する。

## 15. 実装時のP0/P1/P2

### P0（リリース前に必須）

- ガチャデモ統合と個別レア度発光の正しさ
- Theme/カード/ナビ/ホームの統一
- 課金前の確率表示、保証差、広告状態
- 既存ロジック・保存データ・テストの維持
- Reduce Motion、VoiceOverの主要フロー、SE対応

### P1（全体刷新の完成に必須）

- 図鑑、対戦、結果、記録、ランキング、設定を独自componentへ完全移行
- 標準List/segmented/toolbar/alert外観の除去
- 共有画像の高解像度化

### P2（品質調整）

- 背景粒子数、光、影、タイミングの実機微調整
- 国旗cache最適化
- 触覚フィードバック。使用する場合は選択、SSR以上公開、勝敗だけに限定し、端末設定を尊重

## 16. 未確定事項（実装前にCEOまたは秘書判断が必要）

1. **常時バナーの範囲**: 本仕様は「本編開始後はガチャ演出中も表示、タイトル/初回登録/OSシートは除外」と解釈した。ガチャ映像の完全没入を優先して一時非表示にするならCEO確認が必要。
2. **ポイント100回=300枚の閲覧負荷**: 決定仕様どおりSSR以上で停止すると操作回数が多くなる。本仕様はそのまま維持しており、「すべて結果へ」を追加していない。短縮を望む場合は仕様変更になる。
3. **ホームの正式な日本語呼称**: UIは「ホーム」、世界観内の見出しは「EARTH ARCHIVE」と仮定。ストア名は変更しない。
4. **広告SDK**: 現行未組込。SDK固有のバナー寸法、ATT表示、失敗callbackは採用SDK決定後に最終調整する。
5. **効果音**: 承認済みデモは無音・素材なし。本仕様は視覚のみをP0とし、音源制作・ライセンスは対象外。
6. **ライトテーマ**: 世界観優先でアプリ内は常時ダークを推奨。OS設定に合わせて完全ライト化が必要なら別の色検証工程が必要。

## 17. 実装完了の定義

次のすべてを満たした時だけ全体再設計完了とする。

- 本書P0/P1の全項目が実装されている
- 主要画面から標準 `List(.insetGrouped)`、標準segmented Picker、標準TabView外観、標準bordered buttonが見えなくなっている（裏側での利用は可）
- タイトル、ホーム、図鑑、ガチャ、対戦、結果、記録、ランキング、設定、課金/広告が同じtoken/componentを使用している
- 承認済みデモの導入4種と反転光4段階が仕様どおり
- 既存自動テストがすべて通り、追加テストも通る
- iPhone SE、393pt標準、Pro Maxで視覚確認済み
- VoiceOver主要2フロー、Reduce Motion、Dynamic Typeを確認済み
- 作成担当とは別のチェック担当が、本書のチェックリストに基づいて指摘のみを行い、P0指摘が0件
