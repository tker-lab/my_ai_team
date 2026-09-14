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

    /// この国に実際に存在するカードの枚数(通常10。CO2排出量データの無い7カ国は9)。
    /// 豆知識10個の解放ペースは、固定の10ではなくこの実枚数を分母にする
    /// (2026-09-14 バグ修正:9枚国だと分母固定10のままでは10個目が永遠に解放されなかった)。
    private var totalCardsForCountry: Int { cards.count }

    /// 持っている要素カードの種類数。
    private var ownedElementCount: Int {
        owned.ownedElementCount(forCountry: iso3, among: cards)
    }

    /// 解放されている豆知識の数(0〜10)。
    /// 「持っている枚数 ÷ その国の実カード枚数」の比率を10個に割り振る。
    /// 例:実カード9枚の国は9枚集め切った時点で10個全部解放される(9÷9×10=10)。
    /// 実カード10枚の国は従来通り1枚集めるごとに1個ずつ解放される。
    private var unlockedTriviaCount: Int {
        guard totalCardsForCountry > 0 else { return 0 }
        return min(10, ownedElementCount * 10 / totalCardsForCountry)
    }

    /// 豆知識index番目(0始まり)を解放するのに必要な所持枚数。
    /// 例:実カード9枚の国でindex=8,9(9個目・10個目)は両方とも9枚必要
    /// (最後の1枚を集めた瞬間に2個まとめて解放される)。
    private func cardsNeeded(forTriviaIndex index: Int) -> Int {
        guard totalCardsForCountry > 0 else { return 0 }
        // ceil((index+1) * total / 10)
        return ((index + 1) * totalCardsForCountry + 9) / 10
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
                        let needed = max(0, cardsNeeded(forTriviaIndex: index) - ownedElementCount)
                        Label("要素カードをもう\(needed)種類集めると解放されます", systemImage: "lock.fill")
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
