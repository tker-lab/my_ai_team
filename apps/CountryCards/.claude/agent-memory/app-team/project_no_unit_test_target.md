---
name: project-no-unit-test-target
description: CountryCardsにはUnitTestターゲットが無い(UIテストのみ)。データ変更の検証方法
metadata:
  type: project
---

CountryCards.xcodeprojにはCountryCardsUITests(UI操作テスト)しかなく、ロジック単体の
Unit Testターゲットが存在しない(2026-09-14時点)。

**Why:** trivia.json(国データ)のマージ作業で、TriviaDatabase.swiftが全件正しく
読み込めるかを確認しようとしたところ、xcodebuildで実行できるUnit Testが無かった。

**How to apply:** JSON等のリソースファイルを差し替える系の作業を検証する時は、
1) 対象のCodable構造体と同じ定義をscratchpadに`.swift`ファイルとして書き出し、
`swift <file>.swift`で実データをデコードして件数・スキーマを確認する(数秒で終わる)、
2) 加えて`xcodebuild -project CountryCards.xcodeproj -scheme CountryCards -destination 'generic/platform=iOS Simulator' build`でビルドが通ることを確認し、
DerivedData配下のビルド済み.app内にリソースが正しくコピーされているかも見る、
の2段構えで代用するとよい。将来Unit Testターゲットを追加する提案をしてもよい。
