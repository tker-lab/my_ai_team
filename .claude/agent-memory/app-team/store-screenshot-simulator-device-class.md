---
name: store-screenshot-simulator-device-class
description: App Store提出用スクリーンショットで指定される「6.9インチ」等の機種クラスのシミュレーターが既定で入っていない時の対処法
metadata:
  type: project
---

App Store Connect提出用のスクリーンショットは「iPhone 16 Pro Max相当(6.9インチクラス)」のように機種クラスを指定されることが多いが、環境に既定で入っているシミュレーターは別の世代(例:iPhone 17 Pro Max)だけ、ということがある。

**確認・対処の手順:**
1. `xcrun simctl list devices available` で今インストール済みの機種を確認
2. 指定機種が無くても、`xcrun simctl list devicetypes` に該当の「デバイスタイプ定義」自体は入っていることが多い(Xcodeに機種定義とOSランタイムは別々に同梱されているため)
3. 入っていれば `xcrun simctl create "<好きな名前>" "<デバイスタイプID>" "<ランタイムID>"` でその場で新規作成できる(例:`com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max` + `com.apple.CoreSimulator.SimRuntime.iOS-26-5`)
4. 作成したシミュレーターは `xcrun simctl boot`→`bootstatus -b`で起動を待ってから使う。解像度は`sips -g pixelWidth -g pixelHeight`で確認でき、Appleが規定する「6.9インチディスプレイ用」解像度(1320×2868px)と一致することを確認できた
5. 作業後、恒久的に使わないシミュレーターは`simctl shutdown`→`simctl delete`で片付けてよい(プロジェクトのgit管理外なので消しても実害なし)

**Why:** Country Cards Collectionのストア掲載準備で「iPhone 16 Pro Max」を指定されたが、環境には「iPhone 17 Pro Max」しか無かった。デバイスタイプ自体は複数世代分Xcodeに同梱されているため、無いと思ってすぐ代替機種で妥協せず、まず`simctl list devicetypes`を確認する価値がある。

**How to apply:** 「指定機種のシミュレーターが無い」と思った時、代替機種で妥協する前にこの手順を試す。特にストア審査提出用の画面サイズなど、機種の正確性が問われる場面で有効。[[xcuitest-screenshot-visual-verification-technique]]と組み合わせて使うことが多い。
