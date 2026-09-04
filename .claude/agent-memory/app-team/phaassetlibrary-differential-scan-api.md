---
name: phaassetlibrary-differential-scan-api
description: 写真ライブラリの増減を「差分だけ」取得するPHPersistentChangeToken系APIの実際に動作したSwiftコード形
metadata:
  type: project
---

写真ライブラリ(PhotoKit)で「前回起動時からの追加・更新・削除だけ」を取得するAPI(iOS16+)。PhotoTimerアプリで実装・ビルド成功・動作確認済み。

```swift
// 起動時に1回。前回保存したトークンと比較する
let previousToken: PHPersistentChangeToken? = /* UserDefaultsから復元 */

if let previousToken {
    do {
        let changes = try PHPhotoLibrary.shared().fetchPersistentChanges(since: previousToken)
        var inserted = Set<String>(), updated = Set<String>(), deleted = Set<String>()
        for change in changes {
            guard let details = try? change.changeDetails(for: .asset) else { continue }
            inserted.formUnion(details.insertedLocalIdentifiers)
            updated.formUnion(details.updatedLocalIdentifiers)
            deleted.formUnion(details.deletedLocalIdentifiers)
        }
        // inserted/updated分だけ PHAsset.fetchAssets(withLocalIdentifiers:) で軽く取得すればよい
    } catch {
        // トークンが古すぎて失効している場合はここに来る。全件再構築にフォールバックする
    }
} else {
    // 初回起動。しおりが無いので全件を対象として扱う
}

// 次回のために更新
let newToken = PHPhotoLibrary.shared().currentChangeToken
// NSKeyedArchiver.archivedData(withRootObject: newToken, requiringSecureCoding: true) でUserDefaultsに保存
```

**ポイント**:
- `fetchPersistentChanges(since:)` は同期のthrowingメソッド(async不要)。ただし軽くない可能性があるため画面スレッドでは呼ばない([[mainactor-background-work-pattern]]参照)
- `change.changeDetails(for: .asset)` で写真・動画に限定した変化を取り出す(`.collection`等も指定可能だが未使用)
- トークン失効時(`catch`に入った時)は全件走査にフォールバックするしかない。ただし初回起動以外で頻繁には起きない想定
- 削除されたIDは `PHAsset` を再取得できない(もう存在しないため)。削除時の後処理(自前のキャッシュから該当分を引き算する等)は「削除されたIDそのもの」だけで完結する設計にしておく必要がある(PhotoTimerでは緯度経度の集計から差し引く処理・解析キャッシュの削除に使った)

**How to apply**: 他のアプリで「写真ライブラリの増減を監視したい」ケースがあれば流用可能。離乳食管理アプリ等で写真添付機能を作る場合にも使えるかもしれない。
