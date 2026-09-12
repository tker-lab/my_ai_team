---
name: xcuitest-accessibility-combine-and-cell-index-traps
description: .accessibilityElement(children:.combine)で識別子を付けると要素の型がOtherではなく中身依存(StaticText等)になり型指定クエリが失敗する。ListのSection内の注意書き行もcellsに数えられ、インデックスがずれる
metadata:
  type: project
---

## `.accessibilityElement(children: .combine)` + `.accessibilityIdentifier()` は要素の型を変える
SwiftUIのVStack/ZStackにタップ領域として`.accessibilityIdentifier("foo")`だけを付けても、
子要素がバラバラのアクセシビリティ要素として露出してしまい、UIテストから見つからない。
`.accessibilityElement(children: .combine)`を先に付けると1つの要素にまとまるが、その結果の
**型は中身によって決まる**(Textが支配的だと`StaticText`になり、`app.otherElements["foo"]`
では見つからない)。国カードバトルのガチャ演出エリアで発生(2026-09-12)。
**Why:** `otherElements`/`buttons`など型指定のクエリは、実際の型と一致しないと`waitForExistence`が
永遠に失敗し、テストがタイムアウトするまで原因が分かりにくい。
**How to apply:** `.accessibilityElement(children: .combine)`を使った要素をUIテストから探す時は、
型を決め打ちせず`app.descendants(matching: .any)["identifier"]`で探す。原因が分からない失敗が出たら
`app.debugDescription`を一時的にprintしてツリーの実際の型を確認する。

## ListのSection内にある「注意書き」テキストの行も`cells`にカウントされる
```swift
Section {
    CollectionScopeNoticeView() // ただのText、NavigationLinkではない
}
ForEach(items) { NavigationLink(...) }
```
のような構成だと、`app.cells.element(boundBy: 0)`は注意書きの行を指してしまい、タップしても
何も起きない(ナビゲーションしない)。実際のデータ行は`boundBy: 1`から始まる。
**Why:** UIKit/SwiftUIのList実装では、Section内の非NavigationLink行も等しく1つの
テーブルセルとして扱われるため、「先頭のcellが本題の1件目」という思い込みが外れる。
**How to apply:** Listに固定の注意書き・バナー行を入れる画面のUIテストでは、cellのインデックスを
1つずらすか、`app.cells.containing(.staticText, identifier: "...")`のように内容で絞り込む。
