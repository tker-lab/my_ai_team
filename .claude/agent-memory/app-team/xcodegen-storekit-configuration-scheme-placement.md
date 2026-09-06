---
name: xcodegen-storekit-configuration-scheme-placement
description: xcodegenでStoreKitテスト設定ファイルをスキームに紐付けるには、run:/test:それぞれの中にstoreKitConfigurationキーを書く必要がある(スキーム直下やtest:配下は反映されないケースあり)
metadata:
  type: project
---

PhotoTimerの課金機能(2026-09-06)実装時、`project.yml`の`schemes.<name>`直下に
`storeKitConfiguration: <path>`と書いても反映されなかった。バイナリのstrings調査で
`storeKitConfiguration`キーは`run:`(LaunchAction)と`test:`(TestAction)それぞれの
設定ブロックの中の項目だと判明し、`run:`配下に置いたところLaunchAction(通常の実行・
CEOが試す時)には反映された。一方`test:`配下に同じキーを置いても、xcodegen 2.46.0では
TestActionへの反映が確認できず(原因未特定)、`xcodegen generate`後に生成された
`.xcscheme`のXMLへ`<StoreKitConfigurationFileReference>`タグを直接手動追記して回避した
(ただし次に`xcodegen generate`を実行するとこの手動パッチは消えるため、毎回再追記が必要)。

**How to apply:** 他アプリでStoreKitテストをxcodegen経由で設定する時は、まず`run:`配下に
`storeKitConfiguration`を書けば通常の実行(CEOがXcodeから試す・実機で試す)は動く。
`xcodebuild test`(UIテストからの購入フロー検証)まで必要な場合は、TestActionへの反映を
毎回確認し、反映されていなければ`.xcscheme`を手動パッチする対応が要る。
