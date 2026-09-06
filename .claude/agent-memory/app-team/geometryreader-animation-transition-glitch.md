---
name: geometryreader-animation-transition-glitch
description: SwiftUIでGeometryReaderを含むViewを.transition()+.id()で差し替え、それを.animation(value:)でアニメーションさせると、切り替わりの瞬間にレイアウトが一時的に不正確なサイズで計算されることがある
metadata:
  type: project
---

PhotoTimerの演出パターン(結婚式ムービー風等)で、写真が「画面の一部にしか表示されない」
「前後の間が重なって見える」不具合が実機・シミュレータ両方で発生した(2026-09-06)。

**原因:** GeometryReaderでレイアウトするView(フルスクリーン表示・コラージュ表示)を
`.transition()`+`.id()`で差し替え、その差し替えを`.animation(value:)`でアニメーションさせていた。
SwiftUIはこの組み合わせで、差し替わりの瞬間にGeometryReaderのレイアウト計算をアニメーションの
一部として扱ってしまい、一時的に不正確な(小さすぎる)サイズを返すことがある。しかも
`.animation(value:)`はそれを付けたView自身だけでなく、離れた場所にあるGeometryReaderを含む
兄弟Viewの切り替わりにまで影響することがあり、原因箇所の特定が難しい。

**直し方(実装した回避策):** `.transition()`+`.id()`によるSwiftUI標準の差し替えに頼らず、
新旧のViewを両方とも「完成したレイアウト」でマウントしたまま残し(=GeometryReaderの計算は
アニメーションの外で先に確定させる)、消えていく側の不透明度(および必要ならscale)**だけ**を
`withAnimation`で動かす、手動クロスフェード方式に書き換える。

**Why:** GeometryReaderはドキュメント化されていない癖として、自分と直接関係ない
アニメーション中でも一時的に不正確な値を返すことがある(SwiftUIコミュニティでも既知の問題)。
`.frame(maxWidth: .infinity, maxHeight: .infinity)`だけでは根本解決にならず、
アニメーションの対象からGeometryReaderのレイアウト計算そのものを外す必要があった。

**How to apply:** GeometryReaderを使うViewを条件分岐やid変更で差し替える設計をする時は、
`.animation(value:)`をそのView(または祖先)に掛けないこと。切り替えの見た目(フェード等)が
欲しい場合は、上記の「両方マウントして不透明度だけ動かす」パターンを使う。他部署(特に
ライフサポート部など、写真・動画・複雑なレイアウトを扱うアプリを作る場合)にも当てはまる
一般的なSwiftUIの注意点。詳細な実装例は`apps/PhotoTimer/PhotoTimer/Views/PresentationFrameView.swift`
の`advanceToNewFrame()`参照。
