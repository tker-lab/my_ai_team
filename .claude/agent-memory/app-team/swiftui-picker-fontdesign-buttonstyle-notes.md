---
name: swiftui-picker-fontdesign-buttonstyle-notes
description: SwiftUIの.pickerStyle(.inline)重複ラベル対策、.fontDesign()が効かないケース、カスタムButtonStyleでの無効化時ドリム対応の3点セット
metadata:
  type: project
---

PhotoTimerのUI調整(2026-09-06、テーマ字体・Picker表示・振り返り一覧ボタン視認性)で確認した、
他の画面実装でも再利用できるSwiftUIの挙動3点。

**1. `.pickerStyle(.inline)` はPickerのラベル引数を枠内の一番上に選択不可の見出しとして
表示してしまう。** Section見出しと重複して紛らわしい場合、`.labelsHidden()` を追加すれば
視覚的にだけ隠せる(VoiceOray用のラベル自体は`Picker("ラベル", selection:)`の引数のまま残る
ので、アクセシビリティは壊れない)。`Picker(selection:) { } label: { }`の形に書き換える必要はない。

**2. `.fontDesign(_:)` という環境値ベースのモディファイアは、`Font.system(size:weight:design:)`
のように呼び出し側で明示的にdesignを指定しているFontには効かない。** 明示的に`.rounded`等を
指定している箇所(例:大きな時刻表示)までテーマの字体に合わせたい場合は、その`design:`引数に
直接`theme.fontDesign`を渡す必要がある(環境値だけ設定しても上書きされない)。

**3. カスタムButtonStyleでも`@Environment(\.isEnabled) private var isEnabled`を
ButtonStyle構造体に生やせば、`.disabled(true)`状態を検知して見た目(不透明度など)を
自前で暗くできる。** ButtonStyleはViewではないが、SwiftUIがmakeBody呼び出し時に環境値を
正しく解決してくれるため、標準スタイル(.bordered等)を使わず完全に自作したボタン見た目でも
無効化時のフィードバックを失わずに済む(PhotoTimerのHistoryActionButtonStyle参照)。
