import Foundation

/// 1回分のガチャ結果(3枚)。演出側はこの配列を先頭から順に見せていく。
struct GachaPullResult {
    let cards: [Card]

    /// この回に含まれる中で一番高いレア度。導入映像を4パターン
    /// (N/SRのみ・SSR・UR・HURの4種)に出し分けるために使う。
    var highestRarity: Rarity {
        cards.map(\.rarity).max() ?? .n
    }
}

/// 複数回まとめて引いた時、一番最後の1枚だけに掛かる「最低保証」。
/// (「¥100の10連の30枚目」「ポイント10連の30枚目」「ポイント100連の300枚目」の
/// ように、まとめ買いの一番最後の1枚だけに適用される。10連の中の他の回・
/// 100連の途中の回には掛からない=それぞれの回はいつも通り「3枚目はSR以上確定」
/// のルールだけが働く)
enum FinalCardGuarantee {
    case none
    case srOrAbove
    case ssrOrAbove
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

    /// SR以上確定の内訳の目安(通常の3枚目、および「10連の最後をSR以上確定」に使う)。
    private static let srPlusWeights: [Rarity: Double] = [
        .sr: 0.82, .ssr: 0.15, .ur: 0.03,
    ]

    /// SSR以上確定の内訳(¥100の10連・ポイント100連の最後の1枚に使う)。
    /// 「URが確定するわけではない」ので、通常のSSR:UR = 6:2の比率のまま
    /// 正規化しただけ(75%:25%)。
    private static let ssrPlusWeights: [Rarity: Double] = [
        .ssr: 0.75, .ur: 0.25,
    ]

    /// ダブりループ対策(案1):ポイントで引くガチャでは、レア度が決まった
    /// 「後」に、同じレア度の中でも未所持のカードを何倍か当たりやすくする。
    /// レア度の抽選確率そのもの(N70%など)は一切変えない、という決定事項に
    /// 対応するため、重み付けは必ずこの後段(同ランク内の抽選)だけにかける。
    struct UnownedBonus {
        /// 未所持カードに掛ける重みの倍率(所持済みは常に1.0倍)。
        /// 【暫定判断】具体的な倍率はapp_team_country_cards.mdで
        /// 「部署に一任」とされているため、まずは4倍で始める
        /// (「出やすいが絶対ではない」を体感しやすい、キリのよい数字)。
        var multiplier: Double = 4.0
        var isOwned: (Card) -> Bool
    }

    private let cardsByRarity: [Rarity: [Card]]
    /// この要素専用の特別カード(北朝鮮のGDP要素だけ存在する)。
    private let specialCard: Card?

    init(cardsForElement: [Card], specialCard: Card?) {
        self.cardsByRarity = Dictionary(grouping: cardsForElement, by: \.rarity)
        self.specialCard = specialCard
    }

    /// ガチャを1回(3枚)引く。
    /// - Parameters:
    ///   - finalCardGuarantee: まとめ買いの一番最後の1枚だけに掛かる最低保証。
    ///     単発の「1回引く」ではnone のままでよい(3枚目は常にSR以上確定という
    ///     基本ルールが別途効いている)。
    ///   - unownedBonus: ポイントガチャの「未所持優先」重み付け。通常のガチャ
    ///     (無料・広告・対戦報酬・課金)ではnilのままにする。
    func drawOnePull(finalCardGuarantee: FinalCardGuarantee = .none, unownedBonus: UnownedBonus? = nil) -> GachaPullResult {
        var cards: [Card] = []
        for slot in 0..<3 {
            let isThirdSlot = slot == 2
            let card: Card
            if isThirdSlot, finalCardGuarantee == .ssrOrAbove {
                card = drawCard(weights: Self.ssrPlusWeights, unownedBonus: unownedBonus)
            } else if isThirdSlot, finalCardGuarantee == .srOrAbove {
                card = drawCard(weights: Self.srPlusWeights, unownedBonus: unownedBonus)
            } else if isThirdSlot {
                card = drawCard(weights: Self.srPlusWeights, unownedBonus: unownedBonus)
            } else {
                card = drawCard(weights: Self.normalWeights, unownedBonus: unownedBonus)
            }
            cards.append(card)
        }
        return GachaPullResult(cards: cards)
    }

    /// 指定した回数だけ連続で引く(10連・100連など)。
    /// 「まとめ買い全体の一番最後の1枚だけ」に `finalCardGuarantee` を適用する
    /// (10連なら30枚目、100連なら300枚目。決定事項どおり、途中の回には掛からない)。
    func drawMultiplePulls(count: Int, finalCardGuarantee: FinalCardGuarantee, unownedBonus: UnownedBonus? = nil) -> [GachaPullResult] {
        (0..<count).map { index in
            let isLastPull = index == count - 1
            return drawOnePull(finalCardGuarantee: isLastPull ? finalCardGuarantee : .none, unownedBonus: unownedBonus)
        }
    }

    /// CPU対戦相手の手札づくり専用:HURを完全に除外した状態で、通常の
    /// 1・2枚目と同じ確率テーブル(N70/SR22/SSR6/UR2)から1枚だけ選ぶ。
    /// 「北朝鮮GDPカードはCPUの手札に絶対に入れない」という決定事項に対応する
    /// (このEngineをCPU用に作る時はspecialCardをnilにして渡すことでも防げるが、
    /// 呼び出し側の実装ミスに備えてこのメソッド自身もHUR抽選を行わない)。
    func drawSingleCardForCPU() -> Card {
        let roll = Double.random(in: 0..<1)
        var cumulative = 0.0
        let orderedRarities: [Rarity] = [.n, .sr, .ssr, .ur]
        for rarity in orderedRarities {
            guard let weight = Self.normalWeights[rarity] else { continue }
            cumulative += weight
            if roll < cumulative, let picked = pickCard(of: rarity, unownedBonus: nil) {
                return picked
            }
        }
        return fallbackCard(preferredOrder: orderedRarities.reversed(), unownedBonus: nil)
    }

    /// レア度ごとの重みに従って1枚選ぶ。まずHUR(超激レア)を判定し、
    /// 外れたら重み配分どおりに通常レア度から選ぶ。
    private func drawCard(weights: [Rarity: Double], unownedBonus: UnownedBonus?) -> Card {
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
            if roll < cumulative, let picked = pickCard(of: rarity, unownedBonus: unownedBonus) {
                return picked
            }
        }
        // 万一(該当レア度のカードが1枚も存在しない等)のフォールバック。
        return fallbackCard(preferredOrder: orderedRarities.reversed(), unownedBonus: unownedBonus)
    }

    /// 指定したレア度の中から1枚選ぶ。`unownedBonus`があれば、未所持のカードほど
    /// 選ばれやすいよう重み付けする(レア度の抽選確率そのものには一切影響しない)。
    private func pickCard(of rarity: Rarity, unownedBonus: UnownedBonus?) -> Card? {
        guard let candidates = cardsByRarity[rarity], !candidates.isEmpty else { return nil }
        guard let unownedBonus else {
            return candidates.randomElement()
        }

        let weights = candidates.map { unownedBonus.isOwned($0) ? 1.0 : unownedBonus.multiplier }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return candidates.randomElement() }

        var roll = Double.random(in: 0..<totalWeight)
        for (card, weight) in zip(candidates, weights) {
            if roll < weight { return card }
            roll -= weight
        }
        return candidates.last
    }

    /// 狙ったレア度のカードが要素内に1枚も存在しない場合の保険。
    /// 高いレア度から順に「実際に存在するカード」を探し、それでも無ければ
    /// 全カードの中からランダムに返す(要素にカードが1枚も無いことは
    /// generate_cards.pyの仕様上あり得ないはずだが、念のため)。
    private func fallbackCard(preferredOrder: [Rarity], unownedBonus: UnownedBonus?) -> Card {
        for rarity in preferredOrder {
            if let card = pickCard(of: rarity, unownedBonus: unownedBonus) {
                return card
            }
        }
        return cardsByRarity.values.flatMap { $0 }.randomElement()!
    }
}
