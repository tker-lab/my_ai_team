---
name: free-apple-id-device-signing
description: 無料Apple ID(Personal Team)でxcodegenプロジェクトを実機に署名・インストールする手順と、team IDを毎回聞き直さないための設定
metadata:
  type: project
---

## Team IDはコマンドラインから特定できない。GUIで一度だけ選んでもらう
Apple Developer Program未加入の無料Apple IDでXcodeにサインイン済みでも、`xcodebuild -allowProvisioningUpdates` だけでは自動的にPersonal TeamのTeam ID(10桁の英数字、例: `ZW257YHSQM`)を選んでくれない。「Signing for "X" requires a development team. Select a development team in the Signing & Capabilities editor.」というエラーで止まる。
**Why:** Team IDはローカルのキャッシュファイル・Keychain等から機械的に読み取る手段が見当たらず(2026-09-04調査済み、PhotoTimerで発生)、Xcode GUIの Signing & Capabilities タブでチームを選ぶ一度きりの操作でしか確定しない。
**How to apply:** このエラーが出たらCEOに「Xcode.appでプロジェクトを開き、対象ターゲット→Signing & Capabilities→Teamで自分の名前を選ぶ」操作を依頼する。選択が終わると `project.pbxproj` に `DEVELOPMENT_TEAM` が書き込まれるので、そこから値を読み取って次項の対応をする。

## xcodegenプロジェクトはDEVELOPMENT_TEAMをproject.ymlにも書く
`.xcodeproj` は`.gitignore`対象でxcodegenが毎回作り直す運用にしているため、CEOがGUIで選んだTeam IDを`project.yml`の`settings.base.DEVELOPMENT_TEAM`に書き込んでおかないと、次にxcodegenを走らせた瞬間に情報が消え、同じGUI操作を再度依頼することになる。
**Why:** [[xcode-setup-mac]]の「.xcodeprojはxcodegenで作れる」运用とセットで守らないと再発する。PhotoTimerで実際に一度失念しかけた。
**How to apply:** 実機署名が絡むプロジェクトでは、Team IDが判明した時点で即座に`project.yml`に反映してxcodegen再生成→ビルド確認までを1セットで行う。

## CODE_SIGN_IDENTITYはSDKごとに分ける
`CODE_SIGN_IDENTITY: "-"`(無署名。シミュレータ向け)を一律指定していると実機ビルドで「entitlements that require signing with a development certificate」エラーになる。`CODE_SIGN_IDENTITY[sdk=iphoneos*]: "Apple Development"` / `CODE_SIGN_IDENTITY[sdk=iphonesimulator*]: "-"` のようにSDK条件付きキーで両方を維持する。
**Why:** シミュレータ向けは証明書不要(無署名で高速)、実機向けは開発者証明書必須という非対称性があるため、片方に寄せると他方が壊れる。
**How to apply:** project.ymlの`settings.base`に上記2行をセットで入れる。xcodegenは`KEY[sdk=...]`形式のキーをそのままXcodeのビルド設定条件に変換してくれる。

## devicectlとxcodebuildで同じ実機のID表記が違う
`xcrun devicectl list devices`は`EAEAFAB7-1FCD-...`のようなUUID形式、`xcodebuild`の`-destination`エラーメッセージは`00008110-000915163411401E`のようなECID形式で、同じ物理デバイスでも別の見た目のIDが出る。どちらを使っても`xcodebuild -destination`は解決できる(内部で同一デバイスとして扱われる)。
**Why:** 別デバイスだと誤認してデバイス探しをやり直さないようにするため。
**How to apply:** `xcodebuild`が「Developer Mode disabled」等のエラーを出す際に添える方のID(ECID形式)は、devicectlのUUID形式と表記が違うだけで同じ端末を指している。

## 「connected (no DDI)」= デベロッパモードがオフ
`xcrun devicectl list devices`の状態欄が`connected (no DDI)`(DDI=Developer Disk Image、Xcodeがデバッグ用にiPhoneへ読み込む追加ファイル)の場合、実機側でデベロッパモードがオフになっている。`xcodebuild`側のエラーメッセージも「enable Developer Mode in Settings → Privacy & Security」と明示される。
**How to apply:** この状態でビルドを試みる前に、CEO(または実機の持ち主)に「設定→プライバシーとセキュリティ→デベロッパモード→オン→再起動→ロック解除後に出る確認ダイアログで「オンにする」」を依頼する。他部署が将来iPhone実機検証をする際にも共通する手順。
