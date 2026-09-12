import Foundation

/// 1回分のガチャ結果(3枚)。演出側はこの配列を先頭から順に見せていく。
struct GachaPullResult {
    let cards: [Card]

    /// この回に含まれる中で一番高いレア度。導入映像を4パターン
    /// (N/SRのみ・SSR・UR・HUR)に出し分けるために使う。
    var highestRarity: Rarity {
        cards.map(\.rarity).max() ?? .n
    }
}

/// 1つの要素(例:人口)専用のガチャの抽選ロジック。
/// 要素ごとに入り口が分かれている(決定事項)ため、要素ごとにこのエンジンを
/// 1つ作って使う想定。
struct GachaEngine {
    /// 北朝鮮のGDPカードが当たる確率。「年末ジャンボ宝くじ1等」を引き合いに
    /// 出せる、キリのよい数字を使う(app_team_country_cards.mdの決定どおり)。
    static let hurChance = 1.0 / 20_000_000.0

    /// 1・2枚目の抽選(渋め案)。合計が1.0になる。
    private static let normalWeights: [Rarity: Double] = [
        .n: 0.70, .sr: 0.22, .ssr: 0.06, .ur: 0.02,
    ]

    /// 3枚目(SR以上確定)の内訳の目安。
    private static let thirdSlotWeights: [Rarity: Double] = [
        .sr: 0.82, .ssr: 0.15, .ur: 0.03,
    ]

    /// ¥100の10連(30枚)の30枚目だけに使う、SSR以上確定の内訳。
    /// 「URが確定するわけではない」ので、通常のSSR:UR = 6:2の比率のまま
    /// 正規化しただけ(75%:25%)。
    private static let tenPullFinalWeights: [Rarity: Double] = [
        .ssr: 0.75, .ur: 0.25,
    ]

    private let cardsByRarity: [Rarity: [Card]]
    /// この要素専用の特別カード(北朝鮮のGDP要素だけ存在する)。
    private let specialCard: Card?

    init(cardsForElement: [Card], specialCard: Card?) {
        self.cardsByRarity = Dictionary(grouping: cardsForElement, by: \.rarity)
        self.specialCard = specialCard
    }

    /// ガチャを1回(3枚)引く。
    /// - Parameter isFinalOfTenPullBatch: ¥100の10連(または将来のポイント10連)の
    ///   10回目にあたる場合はtrue。3枚目がSR以上ではなくSSR以上確定になる。
    func drawOnePull(isFinalOfTenPullBatch: Bool = false) -> GachaPullResult {
        var cards: [Card] = []
        for slot in 0..<3 {
            let isThirdSlot = slot == 2
            let card: Card
            if isThirdSlot && isFinalOfTenPullBatch {
                card = drawCard(weights: Self.tenPullFinalWeights)
            } else if isThirdSlot {
                card = drawCard(weights: Self.thirdSlotWeights)
            } else {
                card = drawCard(weights: Self.normalWeights)
            }
            cards.append(card)
        }
        return GachaPullResult(cards: cards)
    }

    /// 指定した回数だけ連続で引く(10連・100連など)。10回ごとの区切りの
    /// 最後(3枚目)にSSR以上確定を適用するかを `applyTenPullGuarantee` で選べる
    /// (app_team_country_cards.mdの「¥100の10連のみ」という記述に沿って、
    /// 呼び出し側=課金導線かどうかで判断してもらう)。
    func drawMultiplePulls(count: Int, applyTenPullGuarantee: Bool) -> [GachaPullResult] {
        (0..<count).map { index in
            let isLastOfTenBatch = applyTenPullGuarantee && (index + 1) % 10 == 0
            return drawOnePull(isFinalOfTenPullBatch: isLastOfTenBatch)
        }
    }

    /// レア度ごとの重みに従って1枚選ぶ。まずHUR(超激レア)を判定し、
    /// 外れたら重み配分どおりに通常レア度から選ぶ。
    private func drawCard(weights: [Rarity: Double]) -> Card {
        if let specialCard, Double.random(in: 0..<1) < Self.hurChance {
            return specialCard
        }

        let roll = Double.random(in: 0..<1)
        var cumulative = 0.0
        // 辞書のままだと順序が不定になるため、決まった順(N→SR→SSR→UR)で処理する。
        let orderedRarities: [Rarity] = [.n, .sr, .ssr, .ur]
        for rarity in orderedRarities {
            guard let weight = weights[rarity] else { continue }
            cumulative += weight
            if roll < cumulative, let picked = randomCard(of: rarity) {
                return picked
            }
        }
        // 万一(該当レア度のカードが1枚も存在しない等)のフォールバック。
        return fallbackCard(preferredOrder: orderedRarities.reversed())
    }

    private func randomCard(of rarity: Rarity) -> Card? {
        cardsByRarity[rarity]?.randomElement()
    }

    /// 狙ったレア度のカードが要素内に1枚も存在しない場合の保険。
    /// 高いレア度から順に「実際に存在するカード」を探し、それでも無ければ
    /// 全カードの中からランダムに返す(要素にカードが1枚も無いことは
    /// generate_cards.pyの仕様上あり得ないはずだが、念のため)。
    private func fallbackCard(preferredOrder: [Rarity]) -> Card {
        for rarity in preferredOrder {
            if let card = randomCard(of: rarity) {
                return card
            }
        }
        return cardsByRarity.values.flatMap { $0 }.randomElement()!
    }
}
