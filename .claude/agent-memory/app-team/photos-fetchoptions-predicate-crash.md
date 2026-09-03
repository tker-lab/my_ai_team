---
name: photos-fetchoptions-predicate-crash
description: PHFetchOptions.predicateに定数の真偽値NSPredicateを入れるとアプリがクラッシュする(Photosフレームワークの仕様)
metadata:
  type: project
---

## 症状
`PHFetchOptions().predicate = NSPredicate(value: true)`(=「絞り込み条件なし」を表現するための定数predicate)を
設定して `PHAsset.fetchAssets(with:)` 等を呼ぶと、Objective-C例外(`+[PHQuery _filterPredicateFromFetchOptionsPredicate:options:phClass:]`)が投げられ、
キャッチされずアプリ全体がクラッシュする(SIGABRT)。iOS 26.5シミュレータで実機・確認済み(2026-09-04、PhotoTimerアプリ)。

PhotosフレームワークのPHFetchOptions.predicateは「Photosが独自にサポートするキー・演算子の組み合わせ」しか受け付けない特殊なNSPredicateサブセットで、
定数(`NSPredicate(value:)`)はそのサポート対象に含まれない。

## 回避策
絞り込み条件が実質的に「なし」の場合は、`predicate`プロパティに何も代入しない(nilのまま)。
`NSPredicate(value: true)` のような「常にtrue」で代用しようとしない。

## How to apply
今後 [[app-team/*]] で `PHFetchOptions.predicate` を組み立てるコードを書く・レビューする時は、
「絞り込み条件が0件の時にどうなるか」を必ず確認する。定数predicateを入れていないか、実機/シミュレータで
「フィルタなしでスタート」の経路を必ず一度は自動テストか手動で通すこと。

**追記(2026-09-04修正済み)**: PhotoTimerアプリの `CandidateEngine.swift` で実際に修正した。
`buildMetadataPredicate` の戻り値を `NSPredicate?` にして、条件が0件の時は `nil` を返し、呼び出し側
(`fetchBaseAssets`)は `nil` でなければ `options.predicate` に代入する(=元々の代入自体を省略する)形にした。
XCUITestで「絞り込みなしでスタート→クラッシュしない」を確認済み。同種の定数predicateの書き方が他に
無いこともgrepで確認済み(この修正時点でPhotoTimer内には1箇所のみだった)。

## 関連
[[xcuitest-accessibility-id-content-change-detection]] — この不具合はXCUITestの自動確認中に発見した
