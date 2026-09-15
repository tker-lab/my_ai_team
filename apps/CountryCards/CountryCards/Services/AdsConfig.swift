import Foundation

/// AdMob(Googleの広告配信サービス)の広告ユニットID(どの広告枠に広告を出すかを
/// 識別するID)を、ビルドの種類(DEBUG/Release)に応じて安全に切り替えるための
/// 一元管理場所。
///
/// 【なぜテストIDと本番IDを分けるか】
/// 本番の広告ユニットIDのまま開発中のビルド(シミュレーター・実機への都度インストール)
/// で広告を何度も表示・タップすると、Google側から「実際のユーザーによる自然な広告
/// クリックではない」と判定され、AdMobアカウントが無効なクリックの疑いで停止される
/// リスクがある。そのため、開発中は常にGoogleが公式に配布している「テスト用ID」
/// (誰が使っても本物の収益にならず、無限にテストしてよい)を使い、Xcodeが
/// Releaseビルド(App Storeに提出する版)を作る時だけ本物のIDに切り替わるようにする。
///
/// - DEBUG:Xcodeが「Debug」設定でビルドした時に自動で付くフラグ(実機・シミュレーター
///   への通常のインストールはこちら)。
/// - それ以外(Release):App Store提出用のビルドはこちら。
enum AdsConfig {
    /// AdMobの「アプリID」。テスト/本番で共通の値を使う(広告ユニットIDとは別物で、
    /// アプリ自体をAdMobに識別させるための固定ID。Info.plistのGADApplicationIdentifierに
    /// も同じ値を設定している)。
    static let appID = "ca-app-pub-9196912743325616~4281467223"

    /// 画面下部に常時表示するバナー広告のユニットID。
    static var bannerAdUnitID: String {
        #if DEBUG
        // Googleが公式に公開しているテスト用バナー広告ID(固定サイズ320x50)。
        return "ca-app-pub-3940256099942544/2435281174"
        #else
        // 本番用バナー広告ユニットID(常時下部用)。
        return "ca-app-pub-9196912743325616/3615464849"
        #endif
    }

    /// ガチャ追加用リワード広告(視聴完了するとガチャ1回分がもらえる広告)のユニットID。
    static var rewardedAdUnitID: String {
        #if DEBUG
        // Googleが公式に公開しているテスト用リワード広告ID。
        return "ca-app-pub-3940256099942544/1712485313"
        #else
        // 本番用リワード広告ユニットID(ガチャ追加用、報酬名「ガチャ1回」×1)。
        return "ca-app-pub-9196912743325616/1655303889"
        #endif
    }

    /// 今、テスト用IDと本番用IDのどちらを使っているか(ログ表示・確認用)。
    static var isUsingTestAdUnitIDs: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
