import SwiftUI

/// ガチャのトップ画面。要素ごとに入り口が10個ある(決定事項)。
struct GachaHomeView: View {
    @ObservedObject private var database = CardDatabase.shared
    @ObservedObject private var owned = OwnedCollection.shared
    @ObservedObject private var dailyBonus = DailyBonusManager.shared
    @State private var showingPointGacha = false
    @State private var showingIAPGacha = false
    @ObservedObject private var rewardedAd = RewardedAdCoordinator.shared
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            ZStack {
                EarthBackdrop(variant: .gacha(.ssr))
                ScrollView {
                VStack(spacing: 14) {
                    EarthTopBar(title: "探索ガチャ") { ResourceChip(label: "DUP", value: "\(owned.dupePoints)", tint: EarthColors.gold) }
                    HStack(spacing: 10) {
                        NavigationLink { GachaOddsView() } label: { Label("排出確率", systemImage: "percent") }.buttonStyle(EarthActionButtonStyle(variant: .quiet))
                        Button("ポイント") { showingPointGacha = true }.buttonStyle(EarthActionButtonStyle(variant: .secondary))
                        Button("10連") { showingIAPGacha = true }.buttonStyle(EarthActionButtonStyle(variant: .reward))
                    }.padding(.horizontal)
                    dailyStatusBar

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(CardElement.allCases) { element in
                        NavigationLink(value: element) {
                            ElementSigilButton(element: element, detail: collectionDetail(element))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("gachaEntrance_\(element.rawValue)")
                    }
                }
                .padding()
                }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CardElement.self) { element in
                GachaPlayView(element: element)
            }
            .sheet(isPresented: $showingPointGacha) {
                SheetWithAdDock { PointGachaElementListView() }
            }
            .sheet(isPresented: $showingIAPGacha) {
                SheetWithAdDock { IAPGachaElementListView() }
            }
            .overlay(alignment: .top) {
                if let amount = dailyBonus.justGrantedLoginBonus {
                    GameToast(message: "ログインボーナス・無料ガチャ +\(amount)回", kind: .success)
                        .padding().onTapGesture { dailyBonus.justGrantedLoginBonus = nil }
                        .task { try? await Task.sleep(for: .seconds(3)); dailyBonus.justGrantedLoginBonus = nil }
                }
            }
        }
    }

    /// 無料ガチャの残り回数と、広告視聴で増やすボタン。
    /// (チェック工程指摘:1日の回数制限が機能していなかった問題への対応)
    private var dailyStatusBar: some View {
        ArchivePanel { VStack(spacing: 8) {
            Text("無料ガチャ残り \(dailyBonus.freePullsAvailable)回")
                .font(.subheadline.bold())

            if dailyBonus.freePullsAvailable > 0 {
                Text("下の要素を選んでガチャを引く").font(.caption).foregroundStyle(EarthColors.cyan)
            } else if dailyBonus.adBonusRemainingToday > 0 {
                Button("広告を見てガチャを獲得（本日あと\(dailyBonus.adBonusRemainingToday)回）") { rewardedAd.requestPresentation() }
                    .buttonStyle(EarthActionButtonStyle(variant: .reward)).accessibilityIdentifier("rewardedAdAcquireButton")
            } else {
                Text("本日の広告ガチャは終了しました").font(.subheadline.bold()).foregroundStyle(EarthColors.secondary)
            }
            if case .failed(let message) = rewardedAd.state { Text(message).font(.caption).foregroundStyle(EarthColors.coral) }
        }
        }.padding(.horizontal)
    }

    private func collectionDetail(_ element: CardElement) -> String {
        let cards = database.cards(forElement: element)
        return "\(cards.filter(owned.owns).count)/\(cards.count)枚"
    }
}
