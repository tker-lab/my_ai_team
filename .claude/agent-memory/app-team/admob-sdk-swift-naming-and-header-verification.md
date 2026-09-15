---
name: admob-sdk-swift-naming-and-header-verification
description: Google Mobile Ads SDK(AdMob)のSwift API名はGADプレフィックスを外した新命名に統一されている。確実な確認法はxcframeworkのヘッダーをgrepすること
metadata:
  type: project
---

Google Mobile Ads SDK(AdMob、iOS向け広告配信SDK)は、2024年ごろの大きなバージョン(v12以降。2026-09時点の最新は`13.9.0`)から、Swiftから使う時のクラス・関数名がObjective-C由来の`GAD`プレフィックスを外した名前に統一されている。

**旧名(Objective-C・古いSwiftコード例で見かける)→新名(現在のSwift公式ドキュメントの標準)**
- `GADBannerView` → `BannerView`
- `GADRewardedAd` → `RewardedAd`
- `GADRequest` → `Request`
- `GADMobileAds.sharedInstance` → `MobileAds.shared`
- `GADFullScreenContentDelegate` → `FullScreenContentDelegate`
- `GADFullScreenPresentingAd` → `FullScreenPresentingAd`
- `kGADAdSizeBanner`相当 → `AdSizeBanner`(グローバル定数)
- `GADAdSizeFromCGSize(...)` → `adSizeFor(cgSize:)`

Info.plistのキー名(`GADApplicationIdentifier`)や`SKAdNetworkIdentifier`一覧はGADプレフィックスのまま変わっていない(Info.plistは常にObjective-C/C側の命名)。

**なぜこれが起きるか・確実な確認法**:配布されているのは今もObjective-Cのヘッダー(xcframework)一枚で、各クラス宣言に`NS_SWIFT_NAME(NewName)`という注釈が付いており、Clang importerがSwift側にだけ新しい名前で見せている。そのため、公式ドキュメント(developers.google.com/admob/ios/...)のスクレイピングやAI自身の知識だけで名前を推測すると、更新の狭間で古い名前・新しい名前が混在した情報に当たりやすい。

最も確実なのは、SPM(Swift Package Manager)でパッケージを解決した後に実際にダウンロードされるヘッダーファイルを直接grepすること。

```
xcodebuild -resolvePackageDependencies -project <Project>.xcodeproj -scheme <Scheme>
# その後、DerivedData配下のxcframeworkのHeadersディレクトリを探す
find ~/Library/Developer/Xcode/DerivedData -iname "GoogleMobileAds.xcframework"
grep -n "NS_SWIFT_NAME" .../Headers/GADBannerView.h
```

`NS_SWIFT_NAME(...)`の中身がそのままSwiftから呼ぶ時の正式名称になる。ドキュメントの記述と首尾一貫しない箇所(例:一覧表だけ旧名のまま残っている等)があっても、ヘッダーの注釈が常に正。

**汎用性**:AdMobに限らず、Objective-C由来でSwift向けに命名を刷新した外部SDK全般に使える確認手法。SPMで導入した後にヘッダーを直接読む、というアプローチ自体が他のiOS SDK導入作業でも再利用できる。

関連:Country Cards Collectionプロジェクトの詳細は [app_team_country_cards.md](../../../app_team_country_cards.md) の「広告SDK(AdMob)組み込み完了報告」参照。
