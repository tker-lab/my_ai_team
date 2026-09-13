---
name: swiftui-text-int-interpolation-auto-comma
description: SwiftUIのText("...")に整数をそのまま埋め込むと、iOSがロケールに応じて自動でカンマ区切りを付ける(例:1886→1,886)。コードにcomma処理を書いていなくても発生する
metadata:
  type: project
---

`Text("集めたカード \(count)枚")` のように、`Text(_:)`(`LocalizedStringKey`ベースの文字列補間)に`Int`をそのまま埋め込むと、iOSが`IntegerFormatStyle`をロケールに応じて自動適用し、4桁以上の数値に勝手にカンマ区切りを付ける(例:1886が「1,886」と表示される)。ソースコード上はカンマ処理を一切書いていないため、見た目を確認するまで気づきにくい。

**Why:** CountryCards(カンコレ)で「数値表示はカンマ区切りではなく統一する」という指示に対応した際、`Card.displayValue`側(モデル層)は直したのに、`ProfileView`の「集めたカード x / y枚」やポイント表示など、Viewの`Text("...")`内で直接`Int`を補間していた箇所だけカンマが残っていた。原因はSwift標準の文字列補間ではなく、`Text`が`LocalizedStringKey`として解釈し、独自の数値フォーマットを適用していたため。

**How to apply:** SwiftUIで数値をカンマ無しの生の桁で表示したい時は、`Text("\(value)")`のように直接埋め込まず、`Text("\(String(value))")`で明示的に`String`化してから埋め込む(通常のSwift文字列補間に落とし、`LocalizedStringKey`の自動フォーマットを回避する)。同様の症状が出たら、まず「Text直書きの整数補間」を疑って`String(...)`で確認する。関数がすでに`-> String`を返す実装(例:`"\(value)枚"`をComputed Propertyとして返す)は元々問題にならない(そちらはSwift標準のString補間)。
