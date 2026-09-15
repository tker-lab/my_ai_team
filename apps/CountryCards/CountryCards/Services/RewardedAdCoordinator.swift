import SwiftUI
import GoogleMobileAds
import UIKit

/// リワード広告(視聴完了すると報酬がもらえる広告)の読み込み・表示を管理する。
///
/// 【2026-09-15、実SDKに置き換え】これまでは実SDK未接続の間の暫定代用として、
/// アプリ内に自作した「開発用シミュレーション画面」(ボタンを押すと視聴完了扱いに
/// なる画面)を出していたが、今回からGoogleMobileAds SDKの本物のリワード広告に
/// 置き換えた。呼び出し元(GachaHomeView・GachaPlayView)からの使い方は
/// `requestPresentation()`を呼ぶだけで変わらない。実際の広告の表示自体はGoogleの
/// SDKが画面全体に自前でせり出してくる(SwiftUI側でシートを出す必要がない)。
///
/// 【付与ルールは変更なし】「読み込み失敗時・途中終了時は付与しない」という
/// 既存の意図はそのまま維持している。`DailyBonusManager.shared.claimAdBonus()`を
/// 呼ぶのは、広告SDKの「視聴完了(ユーザーが最後まで見て報酬を得た)」コールバック
/// (`present`の`userDidEarnRewardHandler`)の中だけ。
@MainActor
final class RewardedAdCoordinator: NSObject, ObservableObject {
    static let shared = RewardedAdCoordinator()

    enum State: Equatable {
        case idle
        /// 広告を表示している間(タップしてから閉じるまで)。
        case presenting
        case failed(String)
    }
    @Published private(set) var state: State = .idle

    private var rewardedAd: RewardedAd?
    private var isLoadingAd = false

    private override init() {
        super.init()
        // 起動直後から事前に1本読み込んでおく(ボタンを押した瞬間に待たせないため)。
        Task { await loadAd() }
    }

    /// 広告を1本、裏側で読み込んでおく。読み込みには数秒かかることがあるため、
    /// 「ボタンが押されたその場で」ではなく、事前に済ませておく方式にしている。
    private func loadAd() async {
        guard !isLoadingAd, rewardedAd == nil else { return }
        isLoadingAd = true
        defer { isLoadingAd = false }
        do {
            let ad = try await RewardedAd.load(with: AdsConfig.rewardedAdUnitID, request: Request())
            ad.fullScreenContentDelegate = self
            rewardedAd = ad
        } catch {
            // ここでの失敗はユーザー操作の結果ではないので、状態は変えずログのみに
            // 留める(実際に「広告を見てガチャを獲得」を押された時に、まだ準備が
            // できていなければrequestPresentation側が.failedとして知らせる)。
            print("RewardedAdCoordinator: 事前読み込みに失敗しました - \(error.localizedDescription)")
        }
    }

    /// 呼び出し元(ガチャ画面の「広告を見てガチャを獲得」ボタン)から呼ぶ入口。
    /// 従来と同じシグネチャのまま、内部だけ実SDKでの表示に置き換えている。
    func requestPresentation() {
        guard let ad = rewardedAd else {
            // 読み込みがまだ終わっていない・読み込みに失敗した場合。回数は消費しない。
            state = .failed("広告の読み込みに失敗しました。回数は消費していません。")
            Task { await loadAd() }
            return
        }
        guard let root = BannerAdView.topViewController() else {
            state = .failed("広告の表示に失敗しました。回数は消費していません。")
            return
        }
        state = .presenting
        ad.present(from: root) { [weak self] in
            // 視聴完了コールバック。ここで初めてガチャ権を付与する。
            _ = DailyBonusManager.shared.claimAdBonus()
            self?.state = .idle
        }
    }
}

extension RewardedAdCoordinator: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        // 視聴を最後までしなかった(途中で閉じた)場合もここに来るが、
        // 付与は上のuserDidEarnRewardHandlerでしか行われないため、途中終了時は
        // 何も付与されない(既存の意図どおり)。
        if state == .presenting { state = .idle }
        rewardedAd = nil
        Task { await loadAd() } // 次に押された時のために次の1本を読み込んでおく
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        state = .failed("広告の表示に失敗しました。回数は消費していません。")
        rewardedAd = nil
        Task { await loadAd() }
    }
}
