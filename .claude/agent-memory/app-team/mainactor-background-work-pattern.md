---
name: mainactor-background-work-pattern
description: SwiftのTask{}は@MainActorクラスのメソッド内で使っても画面スレッドで動き続ける。バックグラウンド化にはnonisolated+Task.detachedの組み合わせが必要
metadata:
  type: project
---

`@MainActor final class` のメソッド内で `Task { await self.heavyWork() }` と書いても、`heavyWork()` がそのクラスの普通のメソッド(nonisolated指定なし)である限り、実際には画面スレッド(MainActor)上で実行され続ける。`Task{}` は「別スレッドに逃がす」ことを保証せず、呼び出し元のアクター(この場合MainActor)を引き継ぐため。

**症状**: 一見バックグラウンド化したつもりのコードが、写真ライブラリの全走査やVision解析など重い処理を挟むと画面が固まる(PhotoTimerアプリの `LibraryIndex.buildPlaceClusters()`/`sampleCategories()` で実際に発生)。

**正しい直し方**:
1. 重い処理本体を `nonisolated func` にする(`@MainActor` クラスの中でも `nonisolated` を付ければそのメソッドはアクター隔離されない)
2. 呼び出し側は `Task.detached(priority:) { await self.heavyMethod() }` を使う(`Task{}` ではなく `Task.detached`)
3. `@Published` プロパティへの反映だけ `await MainActor.run { self.prop = value }` で画面スレッドに戻す
4. `@MainActor` クラスの `static let shared = Type()` のようなシングルトンは、`nonisolated` メソッドから直接参照すると「main actor-isolated static property」の警告(Swift 6ではエラー)になる。`nonisolated(unsafe)` を安易に付けると初期化子(`init()`)がMainActor隔離のままだとビルドエラーになることがある(実際に発生)。安全な回避策は、参照を取り出す瞬間だけ `let manager = await MainActor.run { Type.shared }` とMainActorへ一度ホップし、以降はその参照経由でnonisolatedメソッドを呼ぶ。
5. クラス内の `private static let someKey = "..."`(定数の文字列など)を nonisolated メソッドから使いたい場合は、その定数自体に `nonisolated private static let ...` を付ける。

**Why**: PhotoTimerアプリのチェック工程で「起動のたびに画面がブロックされる」不具合(原則4違反)の根本原因がこれだった。表面上「Task{}で非同期にしたつもり」のコードが実は同期的にMainActorで動いていた。

**How to apply**: 他のiPhoneアプリ(離乳食管理アプリ・ライフプランシミュレーター等)でも、ViewModelが`@MainActor`(SwiftUIの`ObservableObject`は通常そう)で、その中で重い処理(ファイルI/O、画像解析、ネットワーク等)を「Task{}で逃がしたつもり」で書いていないか確認すること。特にレビュー・実装時のチェックポイントとして有効。関連: [[phaassetlibrary-differential-scan-api]]
