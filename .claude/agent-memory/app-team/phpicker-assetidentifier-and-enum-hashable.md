---
name: phpicker-assetidentifier-and-enum-hashable
description: PHPickerViewControllerでlocalIdentifierを受け取るための設定・enumのHashable自動導出の境界線(PhotoTimer自作リスト機能で確認)
metadata:
  type: project
---

**PHPickerViewControllerでPHAssetのlocalIdentifierを受け取るには `PHPickerConfiguration(photoLibrary: .shared())` で初期化する必要がある。** 空の `PHPickerConfiguration()` のままだと `PHPickerResult.assetIdentifier` が常にnilになる(写真ライブラリへのアクセス権があっても)。編集時に「すでに選ばれている項目」をプリセットしたい場合は `config.preselectedAssetIdentifiers` を使うと、ピッカー終了時の結果配列がそのまま「今回操作後の完全な選択セット」(追加・削除済み)として返る。

**Swiftのenumは、raw value(String/Int等)を持つだけならHashable/Equatableに明示的に準拠宣言しなくても自動的にHashableになる。** 一方、associated valueを持つenum(raw valueなし)は `: Hashable` を明示し、かつassociated valueの型がすべてHashableである時だけ自動導出される。PhotoTimerの `MoodTag`/`CategoryTag`(raw value型)と、絞り込み画面で新設した `Subject`(associated valueでMoodTag/CategoryTagを包む)の実装で、この違いを踏まえて後者にだけ明示的に `Hashable` を宣言した。

**Why:** 自作リスト機能(写真ライブラリから複数選択してリスト化)の実装で、最初 assetIdentifier が全てnilになる問題にぶつかった。原因は `PHPickerConfiguration()` の初期化方法だった。

**How to apply:** 今後どのアプリ(離乳食管理アプリ等)でも「写真ライブラリから複数選んでもらう」機能を作る時は、必ず `photoLibrary: .shared()` を使う。複数のenumを1つの型にまとめて`ForEach`等でHashable制約付きジェネリックに渡す時は、まとめ役のenumに明示的な `Hashable` 宣言が要ることを忘れない。

**もう1点、重大な罠:PHPickerViewControllerは「キャンセルされた」場合と「1枚も選ばずに確定した」場合の両方で、delegateのコールバックに空の結果配列を返す。** この2つはコールバックだけでは区別できない(Apple側の仕様)。「既存の選択済み項目をプリセットして編集する」画面でこれを愚直に「新しい内容」として上書きすると、ユーザーが単にキャンセルしただけのつもりで、リストの中身を全部消してしまう事故になる。PhotoTimerの自作リスト編集画面では「空の結果は無視する(=キャンセル扱い)」という安全側の実装にした。本当に全部消したい時は個別のサムネイルの×ボタンなど、曖昧さの無い別の手段を用意する。
