import SwiftUI

/// ガチャを1回引く画面。「通常モード」「スキップモード」の操作フローを実装する。
/// 演出の作り込み(実際の動画・パーティクル等)はPhase 2に回し、ここでは
/// 状態遷移(タップ待ち→再生→カード表示、の分岐)が動くことを優先している。
struct GachaPlayView: View {
    let element: CardElement
    @StateObject private var viewModel: GachaPlayViewModel
    @ObservedObject private var database = CardDatabase.shared
    @ObservedObject private var dailyBonus = DailyBonusManager.shared
    @ObservedObject private var rewardedAd = RewardedAdCoordinator.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var resultFilter: ResultFilter = .all
    @State private var selectedResultCard: Card?
    @State private var cinematicPackOpen = false
    @State private var awaitingPackOpen = false
    @State private var cinematicTask: Task<Void, Never>?
    @State private var progressOrbit = false
    private enum ResultFilter: String, CaseIterable { case all = "すべて", rare = "SSR+", new = "NEW" }

    init(element: CardElement) {
        self.element = element
        _viewModel = StateObject(wrappedValue: GachaPlayViewModel(
            element: element, database: .shared, owned: .shared, dailyBonus: .shared
        ))
    }

    var body: some View {
        ZStack {
            EarthBackdrop(variant: .gacha(viewModel.pullResult?.highestRarity ?? .n))
            if viewModel.pullResult == nil, viewModel.blockedByDailyLimit {
                noFreePullsView
            } else {
                switch viewModel.phase {
                case .introPaused, .introPlaying:
                    introView
                case .revealing(let index, let faceUp):
                    revealView(index: index, faceUp: faceUp)
                case .done:
                    resultSummaryView
                }
            }
        }
        .foregroundStyle(EarthColors.text)
        .earthNavigationTitle("\(element.displayName)ガチャ")
        .onAppear {
            if viewModel.pullResult == nil {
                viewModel.startPull()
            }
        }
        .onDisappear { cinematicTask?.cancel() }
        .fullScreenCover(isPresented: $rewardedAd.isPresenting) {
            RewardedAdDevelopmentView(coordinator: rewardedAd)
        }
    }

    /// 無料ガチャの残り回数が0の時に出す画面。
    /// 【2026-09-13追加】CEOの実機確認フィードバック対応:「広告を見てもう1回引く」
    /// (本日の広告上限に達していなければ)と「¥100の10連を購入する」の2択を用意する。
    private var noFreePullsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "hourglass")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("本日の無料ガチャ回数を使い切りました")
                .font(.headline)
            Text("ログインボーナス・対戦の勝利でも無料ガチャが増えます。\nダブりポイントがあればそちらもすぐ引けます。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            exhaustedOptionsView
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 「広告を見てもう1回引く」「¥100の10連を購入する」の2択。無料ガチャを
    /// 使い切った直後(noFreePullsView)と、結果画面から「もう一度引く」を押して
    /// 使い切った時(resultSummaryView)の両方から共通で使う。
    private var exhaustedOptionsView: some View {
        VStack(spacing: 12) {
            if dailyBonus.freePullsAvailable > 0 {
                Button("ガチャを引く") { viewModel.startPull() }
                    .buttonStyle(EarthActionButtonStyle())
                    .accessibilityIdentifier("rewardedPullButton")
            } else if dailyBonus.adBonusRemainingToday > 0 {
                Button("広告を見てガチャを獲得（本日あと\(dailyBonus.adBonusRemainingToday)回）") {
                    rewardedAd.requestPresentation()
                }
                .buttonStyle(EarthActionButtonStyle(variant: .reward))
                .accessibilityIdentifier("rewardedAdAcquireButton")
            } else {
                Text("広告で獲得できる本日分は終了しました")
                    .font(.caption).foregroundStyle(EarthColors.secondary)
            }

            NavigationLink {
                IAPGachaView(element: element)
            } label: {
                Text("¥100の10連を購入する")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(EarthActionButtonStyle(variant: .reward))
        }
    }

    // MARK: - 導入演出(通常モード:タップ待ち / 再生中)

    private var introView: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear.frame(width: 1, height: 1).accessibilityElement().accessibilityIdentifier("gachaReceiptCommitted").accessibilityLabel("抽選カード受取済み")
            Button { handleIntroTap() } label: {
                ZStack {
                    GachaStormScene(rarity: viewModel.pullResult?.highestRarity ?? .n,
                                    isPlaying: viewModel.phase == .introPlaying)
                    GachaPackOpening(rarity: viewModel.pullResult?.highestRarity ?? .n,
                                     open: cinematicPackOpen)
                    if viewModel.phase == .introPlaying {
                        Circle().trim(from: 0.08, to: 0.82).stroke(EarthColors.cyan.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 286, height: 286).rotationEffect(.degrees(progressOrbit ? 360 : 0))
                            .animation(reduceMotion ? nil : .linear(duration: 1.6).repeatForever(autoreverses: false), value: progressOrbit)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(GachaImmediateResponseStyle())
            // VStackはそのままだと中の要素がバラバラのアクセシビリティ要素として
            // 扱われ、外側に付けたidentifierがUIテストから見えなくなる。
            // .combineで「1つのタップ領域」としてまとめてからidentifierを付ける。
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("gachaIntroArea")

            // 画面端の「スキップ」ボタン(決定事項:映像が始まった時点で出ている)。
            Button("スキップ") { cinematicTask?.cancel(); viewModel.tapSkip() }
                .buttonStyle(EarthActionButtonStyle(variant: .secondary))
                .padding()
                .accessibilityIdentifier("gachaSkipButton")
        }
    }

    private func handleIntroTap() {
        if viewModel.phase == .introPlaying {
            if awaitingPackOpen {
                awaitingPackOpen = false
                cinematicPackOpen = true
                cinematicTask?.cancel()
                cinematicTask = Task {
                    try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 650))
                    guard !Task.isCancelled else { return }
                    viewModel.finishIntro()
                }
                return
            }
            if cinematicPackOpen {
                cinematicTask?.cancel()
                viewModel.finishIntro()
                return
            }
            cinematicTask?.cancel()
            // 早送りは未開封パックで一度止める。開封は次の明示タップで行う。
            awaitingPackOpen = true
        } else {
            playCinematic()
        }
    }

    private func playCinematic() {
        guard viewModel.beginIntro() else { return }
        cinematicTask?.cancel()
        cinematicPackOpen = false
        awaitingPackOpen = false
        progressOrbit = false
        DispatchQueue.main.async { progressOrbit = true }
        let total = reduceMotion ? 0.35 : ((viewModel.pullResult?.highestRarity == .hur) ? 7.15 : 5.9)
        cinematicTask = Task {
            try? await Task.sleep(for: .seconds(total * 0.72))
            guard !Task.isCancelled else { return }
            cinematicPackOpen = true
            try? await Task.sleep(for: .seconds(total * 0.28))
            guard !Task.isCancelled else { return }
            viewModel.finishIntro()
        }
    }

    // MARK: - カード表示

    private func revealView(index: Int, faceUp: Bool) -> some View {
        ZStack {
            Button {
                viewModel.tapCard()
            } label: {
                ZStack {
                    VStack(spacing: 24) {
                        Spacer()
                        if faceUp, let card = viewModel.pullResult?.cards[index] {
                            CollectibleCardView(card: card, country: database.country(for: card.iso3), size: .hero, emphasis: .featured)
                                .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
                                .accessibilityIdentifier("gachaCardFace")
                        } else if let card = viewModel.pullResult?.cards[index] {
                            CollectibleCardView(card: card, country: nil, size: .hero, revealState: .hidden)
                                .rotationEffect(.degrees(reduceMotion ? 0 : -1.2))
                                .accessibilityIdentifier("gachaCardBack")
                        }
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(GachaImmediateResponseStyle())
            .id(index)
            if faceUp, let card = viewModel.pullResult?.cards[index], card.rarity >= .ssr {
                CardTurnFlash(rarity: card.rarity).id("\(index)-\(card.id)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gachaRevealArea")
    }

    // MARK: - 結果まとめ

    private var resultSummaryView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("観測完了").font(.system(size: 28, weight: .black, design: .rounded)).padding(.top)
                if let indexed = indexedCards.max(by: { $0.card.rarity < $1.card.rarity }) {
                    resultCard(indexed, size: .hero)
                }
                ArchiveSegmentSwitch(items: ResultFilter.allCases.map { ($0, $0.rawValue) }, selection: $resultFilter)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 10)], spacing: 12) {
                    ForEach(filteredCards, id: \.index) { indexed in resultCard(indexed, size: .mini) }
                }

                if viewModel.blockedByDailyLimit {
                    Text("本日の無料ガチャ回数を使い切りました")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top)
                    exhaustedOptionsView
                        .padding(.horizontal, 32)
                } else {
                    Button("もう一度引く") { viewModel.startPull() }
                        .buttonStyle(EarthActionButtonStyle())
                        .padding(.top)
                }
                Spacer().frame(height: 32)
            }
            .padding()
        }
        .sheet(item: $selectedResultCard) { card in SheetWithAdDock { CardDetailOverlay(card: card, country: database.country(for: card.iso3)) } }
    }

    private var indexedCards: [(index: Int, card: Card)] { Array((viewModel.pullResult?.cards ?? []).enumerated()).map { ($0.offset, $0.element) } }
    private var filteredCards: [(index: Int, card: Card)] {
        let heroIndex = indexedCards.max(by: { $0.card.rarity < $1.card.rarity })?.index
        return indexedCards.filter { item in
            guard item.index != heroIndex else { return false }
            switch resultFilter { case .all: return true; case .rare: return item.card.rarity >= .ssr; case .new: return viewModel.isNewByIndex.indices.contains(item.index) && viewModel.isNewByIndex[item.index] }
        }
    }
    private func resultCard(_ item: (index: Int, card: Card), size: CollectibleCardSize) -> some View {
        let isNew = viewModel.isNewByIndex.indices.contains(item.index) && viewModel.isNewByIndex[item.index]
        return VStack(spacing: 5) {
            Button { selectedResultCard = item.card } label: { CollectibleCardView(card: item.card, country: database.country(for: item.card.iso3), size: size, emphasis: isNew ? .new : .standard) }.buttonStyle(.plain)
            Text(isNew ? "NEW" : "DUPLICATE +1pt").font(.caption2.bold()).foregroundStyle(isNew ? EarthColors.gold : EarthColors.secondary)
        }
    }
}

private struct GachaImmediateResponseStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? 0.12 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
