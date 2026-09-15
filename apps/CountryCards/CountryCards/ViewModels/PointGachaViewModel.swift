import Foundation

/// ダブりポイントで引くガチャのロジック。「1回・10回・100回」の3パターンから
/// 選び、通常のガチャと全く同じ確率テーブルを使う(決定事項どおり。レア度の
/// 抽選確率自体は一切変えない)。レア度が決まった後の「どの国のカードか」を
/// 選ぶ段階だけ、未所持のカードを優先する重みを掛ける(ダブりループ対策・案1)。
@MainActor
final class PointGachaViewModel: ObservableObject {
    enum PullCount: Int, CaseIterable, Identifiable {
        case one = 1
        case ten = 10
        case hundred = 100
        var id: Int { rawValue }

        /// 消費ポイント(1回=10pt、10回=100pt、100回=1000pt。決定事項どおり)。
        var cost: Int { rawValue * 10 }

        var displayName: String { "\(rawValue)回引く(\(cost)pt)" }
    }

    let element: CardElement
    @Published private(set) var results: [GachaPullResult] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isNewByCardIndex: [Bool] = []

    private let engine: GachaEngine
    private let owned: OwnedCollection

    init(element: CardElement, database: CardDatabase, owned: OwnedCollection) {
        self.element = element
        self.owned = owned
        let cardsForElement = database.cards(forElement: element)
        let special = element == .gdp ? database.specialCards.first(where: { $0.element == .gdp }) : nil
        self.engine = GachaEngine(cardsForElement: cardsForElement, specialCard: special)
    }

    func canAfford(_ pullCount: PullCount) -> Bool {
        owned.dupePoints >= pullCount.cost
    }

    /// ポイントを消費してガチャを引く。10回なら30枚目がSR以上確定、
    /// 100回なら300枚目がSSR以上確定になる(決定事項どおり)。
    func pull(_ pullCount: PullCount) {
        errorMessage = nil
        guard owned.spendDupePoints(pullCount.cost) else {
            errorMessage = "ポイントが足りません"
            return
        }

        let finalGuarantee: FinalCardGuarantee = {
            switch pullCount {
            case .one: return .none // 単発は3枚目SR以上確定という通常ルールのみ
            case .ten: return .srOrAbove
            case .hundred: return .ssrOrAbove
            }
        }()

        let unownedBonus = GachaEngine.UnownedBonus(isOwned: { [owned] card in owned.owns(card) })
        var pulls = engine.drawMultiplePulls(
            count: pullCount.rawValue,
            finalCardGuarantee: finalGuarantee,
            unownedBonus: unownedBonus
        )
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestBatchStops"), pullCount != .one {
            let pool = CardDatabase.shared.cards(forElement: element)
            if let low = pool.first(where: { $0.rarity == .n }), let ssr = pool.first(where: { $0.rarity == .ssr }) {
                var cards = Array(repeating: low, count: pullCount.rawValue * 3)
                let stopIndices = pullCount == .ten ? [12, 24] : [20, 70, 140, 220, 290]
                for index in stopIndices where cards.indices.contains(index) { cards[index] = ssr }
                pulls = stride(from: 0, to: cards.count, by: 3).map { GachaPullResult(cards: Array(cards[$0..<min($0 + 3, cards.count)])) }
            }
        }
#endif
        isNewByCardIndex = pulls.flatMap(\.cards).map { owned.receive($0) }
        results = pulls
        owned.recordGachaUse(pullCount: pullCount.rawValue)
        GameCenterManager.shared.syncAllScores(owned: owned, database: .shared)
    }
}
