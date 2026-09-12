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
        VStack(spacing: 16) {
            Text("保有ポイント: \(owned.dupePoints)pt")
                .font(.headline)

            ForEach(PointGachaViewModel.PullCount.allCases) { pullCount in
                Button(pullCount.displayName) {
                    viewModel.pull(pullCount)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canAfford(pullCount))
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }

            if !viewModel.results.isEmpty {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 12) {
                        ForEach(Array(viewModel.results.enumerated()), id: \.offset) { _, pull in
                            ForEach(pull.cards) { card in
                                CardView(card: card, country: database.country(for: card.iso3))
                                    .scaleEffect(0.85)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                Spacer()
                Text("10ポイント=ガチャ1回分。未所持のカードほど当たりやすくなっています。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            }
        }
        .padding(.top)
        .navigationTitle("\(element.displayName)(ポイント)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
