import SwiftUI

@MainActor
final class RewardedAdCoordinator: ObservableObject {
    static let shared = RewardedAdCoordinator()
    enum State: Equatable { case idle, presentingDevelopmentSimulation, failed(String) }
    @Published private(set) var state: State = .idle
    @Published var isPresenting = false
    private init() {}

    func requestPresentation() { state = .presentingDevelopmentSimulation; isPresenting = true }
    func completeDevelopmentSimulation() {
        guard state == .presentingDevelopmentSimulation, DailyBonusManager.shared.claimAdBonus() else { return }
        state = .idle; isPresenting = false
    }
    func cancelDevelopmentSimulation() { state = .idle; isPresenting = false }
    func failDevelopmentSimulation() { state = .failed("広告の読み込みに失敗しました。回数は消費していません。"); isPresenting = false }
}

struct RewardedAdDevelopmentView: View {
    @ObservedObject var coordinator: RewardedAdCoordinator
    var body: some View { ZStack { Color.black.ignoresSafeArea(); VStack(spacing: 20) {
        Text("REWARDED AD").font(.title.bold()).foregroundStyle(.white)
        Text("広告SDK未接続・開発用状態遷移シミュレーション").foregroundStyle(.yellow).multilineTextAlignment(.center)
        Text("本番SDK接続後は、広告SDKの視聴完了コールバックだけがガチャ権を付与します。").font(.caption).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
        Button("開発用：最後まで視聴成功") { coordinator.completeDevelopmentSimulation() }.buttonStyle(EarthActionButtonStyle(variant: .reward)).accessibilityIdentifier("rewardedAdComplete")
        Button("途中終了（付与なし）") { coordinator.cancelDevelopmentSimulation() }.buttonStyle(EarthActionButtonStyle(variant: .secondary)).accessibilityIdentifier("rewardedAdCancel")
        Button("読み込み失敗（付与なし）") { coordinator.failDevelopmentSimulation() }.buttonStyle(EarthActionButtonStyle(variant: .danger))
    }.padding(28) } .interactiveDismissDisabled() }
}
