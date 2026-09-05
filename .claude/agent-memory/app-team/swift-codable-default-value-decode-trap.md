---
name: swift-codable-default-value-decode-trap
description: Swiftの自動生成Codableは、構造体にデフォルト値付きプロパティを追加してもJSON側にキーが無ければデコード全体が失敗する。旧保存データが丸ごと既定値に巻き戻る事故を防ぐ書き方。
metadata:
  type: project
---

Swiftで `struct Settings: Codable { var x: Int = 5 }` のように既定値を書いても、自動生成される
`init(from:)` はその既定値を使わない。JSON側に対応するキーが無いと `keyNotFound` でデコードが
丸ごと失敗する。実際に `swift` コマンドで検証済み(2026-09-05, PhotoTimerの `PlaybackSettings` に
`videoAudioMixMode` を追加する際に発覚)。

呼び出し側が `try? JSONDecoder().decode(...)` のように失敗を握りつぶして `.default` にフォールバックする
書き方をしていると、新しいプロパティを1個追加しただけで、**そのプロパティ以外も含めて、
既存ユーザーの保存済み設定が全部まとめて既定値に巻き戻る**(クラッシュはしないので気づきにくい)。

**回避策:** カスタム `CodingKeys` + カスタム `init(from decoder:)` を書き、各プロパティを
`container.decodeIfPresent(_:forKey:) ?? 既定値` で読む。`encode(to:)` は自動生成のままで問題ない
(カスタム `init(from:)` を書いても `Encodable` 側の自動合成は妨げられないことを確認済み)。

```swift
struct Settings: Codable, Equatable {
    var x: Int = 5
    var y: NewEnum = .foo   // 後から追加したプロパティ

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decodeIfPresent(Int.self, forKey: .x) ?? 5
        y = try c.decodeIfPresent(NewEnum.self, forKey: .y) ?? .foo
    }
}
```

**How to apply:** 端末内にJSON等でユーザー設定を保存し、後から項目を増減させる可能性がある
アプリ全般に当てはまる(PhotoTimerに限らない)。ライフサポート部・他のiPhoneアプリでも、
「設定を保存するstruct」を作る時点でこのパターンを最初から使っておくと、後で項目を足すたびに
気を付ける必要が無くなる。既存のstructにこのパターンが無い場合は、次にプロパティを追加する
タイミングで必ず適用する。関連: [[xcode-setup-mac]](同じPhotoTimerプロジェクトの環境構築メモ)。
