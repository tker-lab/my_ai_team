import SwiftUI

/// ¥100の10連ガチャ画面。ポイントガチャと同様、結果は一覧でまとめて見せる。
struct IAPGachaView: View {
    let element: CardElement
    @StateObject private var viewModel: IAPGachaViewModel
    @ObservedObject private var store = StoreManager.shared
    @ObservedObject private var database = CardDatabase.shared

    init(element: CardElement) {
        self.element = element
        _viewModel = StateObject(wrappedValue: IAPGachaViewModel(
            element: element, database: .shared, owned: .shared, store: .shared
        ))
    }

    var body: some View {
        VStack(spacing: 16) {
            if let product = store.product {
                Text("\(product.displayName) — \(product.displayPrice)")
                    .font(.headline)
            } else {
                Text("商品情報を読み込み中です…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await viewModel.purchaseAndPull() }
            } label: {
                if viewModel.isPurchasing {
                    ProgressView()
                } else {
                    Text("¥100で10連を購入(30枚目SSR以上確定)")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.product == nil || viewModel.isPurchasing)

            if let errorMessage = store.errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
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
            }
        }
        .padding(.top)
        .navigationTitle("\(element.displayName)(¥100)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
