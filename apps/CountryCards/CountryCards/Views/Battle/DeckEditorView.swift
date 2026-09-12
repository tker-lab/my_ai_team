import SwiftUI

/// デッキ編成画面。要素ごとに、持っているカードから最大5枚選ぶ
/// (決定事項:自動編成ではなく自分でセットする方式)。
struct DeckEditorView: View {
    @ObservedObject private var database = CardDatabase.shared
    @ObservedObject private var owned = OwnedCollection.shared
    @ObservedObject private var deckManager = DeckManager.shared

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 8)]

    var body: some View {
        List {
            ForEach(CardElement.allCases) { element in
                Section {
                    let ownedCards = database.cards(forElement: element).filter(owned.owns)
                    if ownedCards.isEmpty {
                        Text("まだこの要素のカードを持っていません")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(ownedCards) { card in
                                let inDeck = deckManager.isInDeck(card)
                                Button {
                                    deckManager.toggle(card)
                                } label: {
                                    VStack(spacing: 4) {
                                        CardView(card: card, country: database.country(for: card.iso3))
                                            .scaleEffect(0.55)
                                            .frame(width: 90, height: 125)
                                        Image(systemName: inDeck ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(inDeck ? .green : .secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    let count = (deckManager.cardIDsByElement[element] ?? []).count
                    Text("\(element.displayName)(\(count)/5枚セット中)")
                }
            }
        }
        .navigationTitle("デッキ編成")
    }
}
