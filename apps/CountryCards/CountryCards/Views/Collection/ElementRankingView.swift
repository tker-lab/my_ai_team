import SwiftUI

/// 1要素分のランキング一覧(スコアが高い順)。持っていないカードは国名・数値を隠す。
struct ElementRankingView: View {
    let element: CardElement
    @ObservedObject private var database = CardDatabase.shared
    @ObservedObject private var owned = OwnedCollection.shared
    @State private var selectedCard: Card?

    private var cards: [Card] { database.cards(forElement: element) }

    var body: some View {
        ZStack { EarthBackdrop(variant: .archive)
        ScrollView { LazyVStack(spacing: 8) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                let country = database.country(for: card.iso3)
                let isOwned = owned.owns(card)
                Button {
                    if isOwned { selectedCard = card }
                } label: {
                    HStack {
                        Text("\(index + 1)位")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .leading)
                        Text(isOwned ? (country?.nameJa ?? card.iso3) : "？？？")
                        Spacer()
                        if isOwned {
                            Text(card.displayValue + element.unit)
                                .font(.subheadline)
                        }
                        RarityBadge(rarity: card.rarity)
                    }
                }
                .disabled(!isOwned)
                .foregroundStyle(isOwned ? .primary : .secondary)
                .padding(12).background(EarthColors.panel, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(EarthColors.line))
            }
        }.padding() }}
        .earthNavigationTitle(element.displayName)
        .sheet(item: $selectedCard) { card in
            SheetWithAdDock { CardDetailSheet(card: card, country: database.country(for: card.iso3)) }
        }
    }
}
