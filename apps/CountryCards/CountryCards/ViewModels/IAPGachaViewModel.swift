import Foundation

/// ¥100の10連ガチャ(課金)専用のロジック。無料・ポイントのガチャと同じ
/// GachaEngineを使い、「30枚目はSSR以上確定」だけが違う(決定事項どおり)。
@MainActor
final class IAPGachaViewModel: ObservableObject {
    let element: CardElement
    @Published private(set) var results: [GachaPullResult] = []
    @Published private(set) var isPurchasing = false

    private let engine: GachaEngine
    private let owned: OwnedCollection
    private let store: StoreManager

    init(element: CardElement, database: CardDatabase, owned: OwnedCollection, store: StoreManager) {
        self.element = element
        self.owned = owned
        self.store = store
        let cardsForElement = database.cards(forElement: element)
        let special = element == .gdp ? database.specialCards.first(where: { $0.element == .gdp }) : nil
        self.engine = GachaEngine(cardsForElement: cardsForElement, specialCard: special)
    }

    func purchaseAndPull() async {
        isPurchasing = true
        let success = await store.purchaseTenPull()
        isPurchasing = false
        guard success else { return }

        let pulls = engine.drawMultiplePulls(count: 10, finalCardGuarantee: .ssrOrAbove)
        for pull in pulls {
            for card in pull.cards {
                owned.receive(card)
            }
        }
        results = pulls
        owned.recordGachaUse(pullCount: 10)
        GameCenterManager.shared.syncAllScores(owned: owned, database: .shared)
    }
}
