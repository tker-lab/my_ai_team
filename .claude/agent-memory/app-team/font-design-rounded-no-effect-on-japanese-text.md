---
name: font-design-rounded-no-effect-on-japanese-text
description: SwiftUIのFont.Design(.rounded等)は日本語(漢字・ひらがな・カタカナ)のグリフには効かず、ラテン文字・数字にしか反映されない
metadata:
  type: project
---

PhotoTimerのカラーテーマ機能(ブルー=デフォルト字体/クリーム=丸みのある字体)で、
`.fontDesign(.rounded)` をアプリ全体(Form内の見出し・説明文・ボタン等)に明示適用しても、
画面のほとんどを占める日本語テキスト(「絞り込み条件」「スタート」等)の見た目は
両テーマでほぼ変わらない。これはSwiftUIの実装漏れではなく、**Appleが日本語(Hiragino系)
システムフォントに丸みのあるデザインバリアントを提供していない**という土台の制約による。
`Font.Design` が視覚的に効くのは英数字(ラテン文字・数字)だけで、CJK文字には適用されない。

**How to apply:** CEOやCEO以外から「テーマで字体をもっとはっきり変えたい」という要望が来た時、
`.fontDesign()` の適用範囲を広げる対応(2026-09-06に実施済み。[[swiftui-picker-fontdesign-buttonstyle-notes]]参照)
だけでは日本語テキストの見た目はほぼ変わらないと事前に説明すること。数字表示(タイマーの
残り時間等)やLive Photo等の英字表記には引き続き効果がある。CEOが日本語部分でも
はっきり違いを出したい場合は、フォントウェイト・文字間隔・アクセントカラーの差を強める、
またはカスタムフォントを埋め込む、といった別の手段が必要になる(今回は実施していない)。
