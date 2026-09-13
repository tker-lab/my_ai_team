import SwiftUI

/// ガチャのトップ画面。要素ごとに入り口が10個ある(決定事項)。
struct GachaHomeView: View {
    @ObservedObject private var database = CardDatabase.shared
    @ObservedObject private var owned = OwnedCollection.shared
    @ObservedObject private var dailyBonus = DailyBonusManager.shared
    @State private var showingPointGacha = false
    @State private var showingIAPGacha = false
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                dailyStatusBar

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(CardElement.allCases) { element in
                        NavigationLink(value: element) {
                            GachaEntranceCard(element: element)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("gachaEntrance_\(element.rawValue)")
                    }
                }
                .padding()
            }
            .navigationTitle("ガチャ")
            .navigationDestination(for: CardElement.self) { element in
                GachaPlayView(element: element)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // Menu内にNavigationLinkを直接置くと遷移しないことがあるため、
                    // 排出確率だけは独立したツールバーボタンにする。
                    NavigationLink { GachaOddsView() } label: {
                        Label("排出確率", systemImage: "percent")
                    }
                    .font(.caption)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu("その他の引き方") {
                        // String(...)でカンマ区切りを防ぐ(下記PointGachaViewと同じ理由)。
                        Button("ポイントで引く(\(String(owned.dupePoints))pt)") { showingPointGacha = true }
                        Button("¥100で10連(課金)") { showingIAPGacha = true }
                    }
                    .font(.caption)
                }
            }
            .sheet(isPresented: $showingPointGacha) {
                PointGachaElementListView()
            }
            .sheet(isPresented: $showingIAPGacha) {
                IAPGachaElementListView()
            }
            .alert(
                "ログインボーナス",
                isPresented: Binding(
                    get: { dailyBonus.justGrantedLoginBonus != nil },
                    set: { if !$0 { dailyBonus.justGrantedLoginBonus = nil } }
                )
            ) {
                Button("OK") { dailyBonus.justGrantedLoginBonus = nil }
            } message: {
                Text("無料ガチャ +\(dailyBonus.justGrantedLoginBonus ?? 0)回")
            }
        }
    }

    /// 無料ガチャの残り回数と、広告視聴で増やすボタン。
    /// (チェック工程指摘:1日の回数制限が機能していなかった問題への対応)
    private var dailyStatusBar: some View {
        VStack(spacing: 8) {
            Text("無料ガチャ残り \(dailyBonus.freePullsAvailable)回")
                .font(.subheadline.bold())

            Button {
                // 広告SDKは未組み込みのため、視聴完了をその場でシミュレートする
                // (実際の広告表示はPhase 2で組み込む)。
                dailyBonus.claimAdBonus()
            } label: {
                Text("広告を見て+1回(本日あと\(dailyBonus.adBonusRemainingToday)回)")
            }
            .buttonStyle(.bordered)
            .disabled(dailyBonus.adBonusRemainingToday <= 0)
        }
        .padding(.top)
    }
}

private struct GachaEntranceCard: View {
    let element: CardElement

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 40))
                .foregroundStyle(element.borderColor)
                .shadow(color: element.borderColor.opacity(0.5), radius: 4)
            Text(element.displayName)
                .font(.headline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            // 【2026-09-13修正】単色の薄塗りから、要素の色を軸にしたグラデーションへ
            // (ビジュアル改善依頼対応。要素ごとに色を変えるという既存ルールは維持)。
            LinearGradient(
                colors: [element.borderColor.opacity(0.20), element.borderColor.opacity(0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(element.borderColor, lineWidth: 2)
        )
        .shadow(color: element.borderColor.opacity(0.25), radius: 6, y: 3)
    }
}
