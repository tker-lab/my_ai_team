import SwiftUI

/// ダブりポイントで引く画面。パック開封演出のような「めくる楽しさ」は単発の
/// 通常ガチャ側で味わえるため、ここでは結果を一覧でまとめて見せるシンプルな
/// 作りにしている(10連・100連まで1枚ずつタップさせるのは操作数が多すぎるため)。
struct PointGachaView: View {
    let element: CardElement
    @StateObject private var viewModel: PointGachaViewModel
    @ObservedObject private var owned = OwnedCollection.shared
    @ObservedObject private var database = CardDatabase.shared

    init(element: CardElement) {
        self.element = element
        _viewModel = StateObject(wrappedValue: PointGachaViewModel(element: element, database: .shared, owned: .shared))
    }

    var body: some View {
        ZStack { EarthBackdrop(variant: .gacha(.ssr)); VStack(spacing: 16) {
            // 【2026-09-13修正】Text内の数値がiOSに自動でカンマ区切りされる
            // (例:9,999)のを防ぐため、String(...)で明示的に文字列化する。
            Text("保有ポイント: \(String(owned.dupePoints))pt")
                .font(.headline)

            // App Storeガイドライン3.1.1の趣旨(購入前の確率開示)に合わせ、
            // ポイント消費前にもここから確率を確認できるようにする。
            // ¥100の10連とは保証内容が違う(ポイント10連はSR以上確定、
            // ポイント100連はSSR以上確定)ため、専用のsourceで正しい内容を表示する。
            NavigationLink("排出確率を確認する") {
                GachaOddsView(source: .point)
            }
            .font(.footnote).foregroundStyle(EarthColors.cyan)

            ForEach(PointGachaViewModel.PullCount.allCases) { pullCount in
                Button(pullCount.displayName) {
                    viewModel.pull(pullCount)
                }
                .buttonStyle(EarthActionButtonStyle())
                .disabled(!viewModel.canAfford(pullCount))
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }

            if !viewModel.results.isEmpty {
                BatchObservationView(cards: viewModel.results.flatMap(\.cards), isNew: viewModel.isNewByCardIndex)
            } else {
                Spacer()
                Text("10ポイント=ガチャ1回分。未所持のカードほど当たりやすくなっています。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            }
        }.padding(.horizontal) }
        .padding(.top)
        .earthNavigationTitle("\(element.displayName)(ポイント)")
    }
}
