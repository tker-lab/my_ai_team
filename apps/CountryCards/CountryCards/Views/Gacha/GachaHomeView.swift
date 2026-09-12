import SwiftUI

/// ガチャのトップ画面。要素ごとに入り口が10個ある(決定事項)。
struct GachaHomeView: View {
    @ObservedObject private var database = CardDatabase.shared
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
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
        }
    }
}

private struct GachaEntranceCard: View {
    let element: CardElement

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 40))
                .foregroundStyle(element.borderColor)
            Text(element.displayName)
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(element.borderColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(element.borderColor, lineWidth: 2)
        )
    }
}
