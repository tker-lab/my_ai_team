import Foundation

/// 初回起動時だけ、要素ごとにNレアのカードを5枚ずつ配布する仕組み。
///
/// 【2026-09-13 仕様変更】以前はこれを「デッキ(DeckManager)」の初期値として
/// 扱っていたが、CEOの実機確認フィードバックにより**デッキ編成機能そのものを
/// 廃止**することになった。しかしこの「最初の持ちカード」の配布自体は、
/// デッキと切り離した単純な仕組みとして残す(app_team_country_cards.mdの
/// 重要な設計意図:カードは減らない仕様と合わせて、これにより全プレイヤーが
/// 常に全要素で最低1枚は所持し続け、「対戦のお題に選ばれた要素のカードを
/// 1枚も持っていない」という状況がそもそも起きなくなる)。
///
/// 【重要】BattleViewModelの「まだ使っていない要素からお題を選ぶ」ロジックは、
/// この前提(全要素で最低1枚は所持している)の上に成り立っている。この配布処理を
/// 弱める・条件付きにする変更をする時は、対戦の進行不能が起きないか必ず確認すること。
@MainActor
enum StartingCardsProvisioner {
    private static let defaults = UserDefaults.standard
    private static let hasGrantedKey = "hasGrantedStartingCards"

    /// 初回だけ、要素ごとにNレアを1枚以上ランダムで5枚ずつ付与する。
    /// (2回目以降の呼び出しは何もしない)
    static func grantStartingCardsIfNeeded(database: CardDatabase, owned: OwnedCollection) {
        guard !defaults.bool(forKey: hasGrantedKey) else { return }
        defaults.set(true, forKey: hasGrantedKey)

        for element in CardElement.allCases {
            let nCards = database.cards(forElement: element).filter { $0.rarity == .n }
            guard !nCards.isEmpty else { continue }
            let picked = Array(nCards.shuffled().prefix(5))
            for card in picked {
                owned.receive(card)
            }
        }
    }
}
