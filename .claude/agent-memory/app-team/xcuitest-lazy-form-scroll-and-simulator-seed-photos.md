---
name: xcuitest-lazy-form-scroll-and-simulator-seed-photos
description: XCUITestでForm下部のLazyVGridが見つからない問題と、シミュレータに最初から入っている写真6枚は消せない件
metadata:
  type: project
---

PhotoTimerアプリのチェック工程対応で判明した、XCUITest自動検証まわりの2つの制約。

**1. SwiftUIの `Form` 内で下の方にある `LazyVGrid`(チップ選択UI等)は、画面をスクロールして表示範囲に入るまでXCUITestのアクセシビリティツリーに現れない。**
`app.buttons["花火"].waitForExistence(timeout: 5)` のような素直な待ち方では見つからず失敗する(実際に遭遇)。対策は見つかるまで `app.swipeUp()` を数回繰り返してから探すヘルパーを使うこと:
```swift
func scrollUntilVisible(app: XCUIApplication, element: XCUIElement, maxSwipes: Int = 6) -> Bool {
    if element.waitForExistence(timeout: 2) { return true }
    for _ in 0..<maxSwipes {
        app.swipeUp()
        if element.waitForExistence(timeout: 1) { return true }
    }
    return false
}
```
Form内の要素を触るテストを書く時は、上の方のセクションだけで安心せず、下の方の要素にはこのパターンを使うこと。

**2. Xcodeのシミュレータ(iOS 26.5で確認)は初回起動時から写真アプリに既定のサンプル写真が数枚(この時点で6枚、すべて静止画・動画0本)入っており、`simctl` にもGUI操作にも頼らずこれを0枚にする手段が(この実行環境には)無かった。**
「写真0枚」を厳密にテストしたい場合、新規シミュレータを作ってもこの既定写真が残るため完全な0件は作れない。代替として「動画0本」等、既定写真では絶対に満たされない条件で絞り込むことで、実質的に同じ検証(0件判定が正しく効くか)ができる。

**How to apply**: 他のiPhoneアプリのXCUITestでも、Form/List内の下の方の要素を触る時や「写真ライブラリが空」を前提にしたテストを書く時に、この2点を踏まえること。
