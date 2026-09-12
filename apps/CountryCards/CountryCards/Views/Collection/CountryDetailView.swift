import SwiftUI

/// 1カ国分の詳細。その国について存在する要素カードを、持っているものはそのまま、
/// 持っていないものはシルエットで並べる。
struct CountryDetailView: View {
    let iso3: String
    @ObservedObject private var database = CardDatabase.shared
    @ObservedObject private var owned = OwnedCollection.shared
    @State private var selectedCard: Card?

    private var country: Country? { database.country(for: iso3) }
    private var cards: [Card] {
        // 要素の並び順(CardElement.allCases)に揃えて表示する。
        let byElement = Dictionary(uniqueKeysWithValues: database.cards(forCountry: iso3).map { ($0.element, $0) })
        return CardElement.allCases.compactMap { byElement[$0] }
    }

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(cards) { card in
                    Button {
                        if owned.owns(card) {
                            selectedCard = card
                        }
                    } label: {
                        CardView(card: card, country: country, isRevealed: owned.owns(card))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle(country?.nameJa ?? iso3)
        .sheet(item: $selectedCard) { card in
            CardDetailSheet(card: card, country: country)
        }
    }
}
