import SwiftUI

/// デッキ編成画面。要素ごとに、持っているカードから最大5枚選ぶ
/// (決定事項:自動編成ではなく自分でセットする方式)。
struct DeckEditorView: View {
    @ObservedObject private var database = CardDatabase.shared
    @ObservedObject private var owned = OwnedCollection.shared
    @ObservedObject private var deckManager = DeckManager.shared
    @State private var minimumAlertShown = false

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
                                    if deckManager.toggle(card) == .blockedByMinimum {
                                        minimumAlertShown = true
                                    }
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
                    Text("\(element.displayName)(\(count)/5枚セット中・最低1枚必要)")
                }
            }
        }
        .navigationTitle("デッキ編成")
        .alert("最低1枚は必要です", isPresented: $minimumAlertShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("この要素のお題が対戦で出た時に出すカードが無くなってしまうため、各要素は最低1枚デッキに残す必要があります。")
        }
    }
}
