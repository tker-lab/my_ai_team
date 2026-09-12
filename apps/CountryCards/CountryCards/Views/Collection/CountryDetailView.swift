import SwiftUI

/// 1カ国分の詳細。その国について存在する要素カードを、持っているものはそのまま、
/// 持っていないものはシルエットで並べる。
struct CountryDetailView: View {
    let iso3: String
    @ObservedObject private var database = CardDatabase.shared
    @ObservedObject private var owned = OwnedCollection.shared
    @ObservedObject private var trivia = TriviaDatabase.shared
    @State private var selectedCard: Card?

    private var country: Country? { database.country(for: iso3) }
    private var cards: [Card] {
        // 要素の並び順(CardElement.allCases)に揃えて表示する。
        let byElement = Dictionary(uniqueKeysWithValues: database.cards(forCountry: iso3).map { ($0.element, $0) })
        return CardElement.allCases.compactMap { byElement[$0] }
    }

    /// 持っている要素カードの種類数=解放されている豆知識の数
    /// (決定事項:要素を1種類集めるごとに豆知識が1個ずつ解放される)。
    private var unlockedTriviaCount: Int {
        owned.ownedElementCount(forCountry: iso3, among: cards)
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

            triviaSection
        }
        .navigationTitle(country?.nameJa ?? iso3)
        .sheet(item: $selectedCard) { card in
            CardDetailSheet(card: card, country: country)
        }
    }

    @ViewBuilder
    private var triviaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("豆知識(\(unlockedTriviaCount)/10 解放)")
                .font(.headline)

            if let facts = trivia.facts(for: iso3) {
                ForEach(0..<10, id: \.self) { index in
                    if index < unlockedTriviaCount, index < facts.count {
                        Label(facts[index], systemImage: "lightbulb.fill")
                            .font(.footnote)
                            .foregroundStyle(.primary)
                    } else {
                        Label("要素カードをもう\(index + 1 - unlockedTriviaCount)種類集めると解放されます", systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("この国の豆知識は準備中です。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
