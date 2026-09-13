---
name: xcuitest-screenshot-visual-verification-technique
description: GUI変更(配色・レイアウト調整など)を、CEOに見せる前に自分で目視確認する手法。XCUITest+XCTAttachment+xcresulttoolでスクリーンショットを機械的に取り出せる
metadata:
  type: project
---

見た目(配色・レイアウト・長い文字列の折り返し等)の変更が「実際どう見えるか」を、CEOに見せる前に自分で確認したい時の手法。`xcrun simctl`にはタップ操作用のコマンドが無いため、素の`simctl launch`+`simctl io screenshot`だけでは画面遷移させながらの確認ができない。

**やり方:**
1. 一時的なXCUITest(例:`ZZVisualCheckUITests.swift`)を書き、確認したい画面まで実際にタップで遷移させながら、要所で `let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.lifetime = .keepAlways; add(attachment)` を呼ぶ
2. `xcodebuild test -only-testing:<Target>/ZZVisualCheckUITests` で実行(通常のUIテストと同じ枠組みで動く)
3. 実行後にできる`.xcresult`から`xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>`でPNGを一括抽出できる(ファイル名は`manifest.json`で対応関係が分かる)
4. 抽出したPNGをReadツールで直接見て確認する
5. **確認が終わったら一時テストファイルは必ず削除する**(成果物に残さない。本番のテストスイートに混ぜない)

**Why:** CountryCardsのビジュアル改善依頼(iPhone標準UIっぽさの解消)で、着手前に「本当に良くなったか」「サントメ・プリンシペのような長い国名が実際に収まるか」を確認する必要があったが、GUI操作の手段が無い環境だったため、この手法で自己レビューしてから報告した。実際、この確認によってProfile画面等で数値が「1,886」とカンマ付きで残っていた不具合([[swiftui-text-int-interpolation-auto-comma]])を報告前に発見・修正できた。

**How to apply:** 見た目に関わる修正依頼(バグ修正・デザイン改善)を実装した後、報告前の自己チェックとして使う。特に「本当に直ったか」を文面だけで判断せず、実際の画面を見て確認したい場面で有効。
