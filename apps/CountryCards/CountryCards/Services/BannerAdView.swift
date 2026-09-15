import SwiftUI
import GoogleMobileAds
import UIKit

/// AdMobのバナー広告(320x50の固定サイズ)をSwiftUIの画面に埋め込むための部品。
///
/// UIViewRepresentableは「SwiftUIでは用意されていないUIKit(古い方の画面部品の
/// 仕組み)の部品を、SwiftUIの画面の中に埋め込むための橋渡し役」。Google Mobile Ads
/// SDKのバナー表示部品(BannerView)はUIKit側の部品として提供されているため、
/// この仕組みを使ってRootTabView等のSwiftUI画面に取り込む。
struct BannerAdView: UIViewRepresentable {
    final class Coordinator {
        /// 広告の読み込みリクエストを一度だけ送るためのフラグ。
        /// (SwiftUIはupdateUIViewを画面が更新されるたびに何度も呼ぶため、
        /// 何もガードしないと毎回広告を読み込み直してしまう)
        var hasRequestedLoad = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> BannerView {
        // AdSizeBannerはAdMobが用意している「320x50の標準バナー」サイズの定数。
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdsConfig.bannerAdUnitID
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        guard !context.coordinator.hasRequestedLoad else { return }
        // バナーを画面に貼った直後は、まだウィンドウ(表示先の画面)が完全に
        // 用意できていないことがある。root view controller(広告タップ後の
        // 遷移先を提供する画面)が取得できるようになった時点で1回だけ読み込む。
        guard let root = Self.topViewController() else { return }
        uiView.rootViewController = root
        uiView.load(Request())
        context.coordinator.hasRequestedLoad = true
    }

    /// 今、画面の一番手前に出ているUIKitの画面(UIViewController)を探す。
    /// 広告のクリック後に開く画面(App Store等)の起点として必要。
    static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
