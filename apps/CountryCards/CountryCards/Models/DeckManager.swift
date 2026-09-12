import Foundation

/// プレイヤーの手札(デッキ)。要素ごとに最大5枚、自分で選んでセットする
/// (決定事項:自動編成は不採用。理由はapp_team_country_cards.mdの
/// 「デッキの決め方」参照 — 自動だと引いたばかりの良いカードで毎回上書きされ、
/// ガチャで集める意味が薄れるため)。
@MainActor
final class DeckManager: ObservableObject {
    static let shared = DeckManager()

    private let defaults = UserDefaults.standard
    private let deckKey = "deckCardIDsByElement"
    private let hasSeededInitialDeckKey = "hasSeededInitialDeck"

    /// 要素ごとの、デッキに入っているカードIDの配列(最大5件)。
    @Published private(set) var cardIDsByElement: [CardElement: [String]]

    private init() {
        if let data = defaults.data(forKey: deckKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            var result: [CardElement: [String]] = [:]
            for (key, value) in decoded {
                if let element = CardElement(rawValue: key) {
                    result[element] = value
                }
            }
            self.cardIDsByElement = result
        } else {
            self.cardIDsByElement = [:]
        }
    }

    private func save() {
        let encoded = Dictionary(uniqueKeysWithValues: cardIDsByElement.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(encoded) {
            defaults.set(data, forKey: deckKey)
        }
    }

    func deckCards(for element: CardElement, database: CardDatabase) -> [Card] {
        let ids = cardIDsByElement[element] ?? []
        let allCards = database.cards(forElement: element) + database.specialCards.filter { $0.element == element }
        let byID = Dictionary(uniqueKeysWithValues: allCards.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    func isInDeck(_ card: Card) -> Bool {
        (cardIDsByElement[card.element] ?? []).contains(card.id)
    }

    /// `toggle(_:)`の結果。DeckEditorViewが「なぜ変更できなかったか」を
    /// 案内できるようにするための列挙。
    enum ToggleResult {
        case added
        case removed
        /// 各要素は最低1枚残す必要があるため、最後の1枚は外せなかった
        /// (チェック工程指摘:0枚にできると対戦でそのお題が来た時に進行不能になるため)。
        case blockedByMinimum
        case blockedByMaximum
    }

    /// デッキへの出し入れ(要素ごとに最低1枚・最大5枚)。
    @discardableResult
    func toggle(_ card: Card) -> ToggleResult {
        var current = cardIDsByElement[card.element] ?? []
        if let index = current.firstIndex(of: card.id) {
            guard current.count > 1 else { return .blockedByMinimum }
            current.remove(at: index)
            cardIDsByElement[card.element] = current
            save()
            return .removed
        } else {
            guard current.count < 5 else { return .blockedByMaximum }
            current.append(card.id)
            cardIDsByElement[card.element] = current
            save()
            return .added
        }
    }

    /// 初回起動時だけ、要素ごとにNレアを5枚ずつランダムでガチャを引かせ、
    /// 初期デッキ50枚(全てN)を持った状態にする(決定事項どおり)。
    func seedInitialDeckIfNeeded(database: CardDatabase, owned: OwnedCollection) {
        guard !defaults.bool(forKey: hasSeededInitialDeckKey) else { return }
        defaults.set(true, forKey: hasSeededInitialDeckKey)

        for element in CardElement.allCases {
            let nCards = database.cards(forElement: element).filter { $0.rarity == .n }
            guard !nCards.isEmpty else { continue }
            let picked = Array(nCards.shuffled().prefix(5))
            for card in picked {
                owned.receive(card)
            }
            cardIDsByElement[element] = picked.map(\.id)
        }
        save()
    }
}
