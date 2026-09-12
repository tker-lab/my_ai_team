import Foundation

/// 対戦(CPU戦)1回分の進行を管理する。
///
/// ルール(app_team_country_cards.mdの決定事項どおり):
/// - 毎ターン「どの要素で比べるか」「高い方/低い方どちらが勝ちか」を両方ランダムに決める
/// - CPUの手札は、要素ごとに1枚、そのターンごとにガチャと同じ確率でランダムに
///   抽選し直す(HUR無し・固定デッキではない)
/// - 北朝鮮GDPカード(HUR)はどのお題でも必ず勝つジョーカー
/// - 【暫定判断】対戦の決着方法(何ターンで勝敗を決めるか)は決定事項に無かったため、
///   5ターン中、勝ちが多い方が対戦の勝者、という分かりやすい形にした
@MainActor
final class BattleViewModel: ObservableObject {
    struct RoundResult: Identifiable {
        let id = UUID()
        let element: CardElement
        let highWins: Bool
        let playerCard: Card
        let cpuCard: Card
        let playerWon: Bool
    }

    enum Phase: Equatable {
        case choosingCard(element: CardElement, highWins: Bool)
        case revealing(round: Int)
        case finished
    }

    static let totalRounds = 5

    @Published private(set) var phase: Phase
    @Published private(set) var roundResults: [RoundResult] = []
    @Published private(set) var pendingCPUCard: Card?

    private let database: CardDatabase
    private let deckManager: DeckManager
    private let owned: OwnedCollection

    var playerWinCount: Int { roundResults.filter(\.playerWon).count }
    var cpuWinCount: Int { roundResults.filter { !$0.playerWon }.count }
    var currentRoundNumber: Int { roundResults.count + 1 }

    init(database: CardDatabase, deckManager: DeckManager, owned: OwnedCollection) {
        self.database = database
        self.deckManager = deckManager
        self.owned = owned
        let element = CardElement.allCases.randomElement()!
        self.phase = .choosingCard(element: element, highWins: Bool.random())
        self.pendingCPUCard = Self.drawCPUCard(for: element, database: database)
    }

    func deckCards(for element: CardElement) -> [Card] {
        deckManager.deckCards(for: element, database: database)
    }

    /// プレイヤーがデッキの中から1枚選んでその回に出す。
    func choose(_ playerCard: Card) {
        guard case .choosingCard(let element, let highWins) = phase,
              let cpuCard = pendingCPUCard else { return }

        let playerWon = Self.resolveWinner(playerCard: playerCard, cpuCard: cpuCard, highWins: highWins)
        roundResults.append(RoundResult(
            element: element, highWins: highWins,
            playerCard: playerCard, cpuCard: cpuCard, playerWon: playerWon
        ))
        phase = .revealing(round: roundResults.count)
    }

    /// 火花演出を見終わったら次のターンへ(または対戦終了へ)進む。
    func proceedAfterReveal() {
        guard case .revealing = phase else { return }
        if roundResults.count >= Self.totalRounds {
            finish()
            return
        }
        let element = CardElement.allCases.randomElement()!
        pendingCPUCard = Self.drawCPUCard(for: element, database: database)
        phase = .choosingCard(element: element, highWins: Bool.random())
    }

    private func finish() {
        phase = .finished
        if playerWinCount > cpuWinCount {
            owned.recordBattleWin()
            // 【暫定判断】対戦の勝利報酬。決定事項には「ガチャの回数が増える」との
            // 方針はあるが、具体的な仕組み(1日3回までの管理場所)はPhase 2で
            // ガチャの入手手段全体(ログイン・広告・対戦)を作る時にまとめて実装する
            // 前提で、今回はダブりポイントを5pt付与する簡易な報酬にしている。
            _ = owned.receiveBattleWinBonus()
            GameCenterManager.shared.syncAllScores(owned: owned, database: database)
        }
    }

    /// CPUの手札をその場で抽選する(HURは除外。決定事項どおり)。
    private static func drawCPUCard(for element: CardElement, database: CardDatabase) -> Card {
        let cardsForElement = database.cards(forElement: element)
        let engine = GachaEngine(cardsForElement: cardsForElement, specialCard: nil)
        return engine.drawSingleCardForCPU()
    }

    /// 勝敗判定。北朝鮮GDPカード(HUR)はどちらの向きでも必ず勝つ。
    private static func resolveWinner(playerCard: Card, cpuCard: Card, highWins: Bool) -> Bool {
        if playerCard.isSpecial { return true } // HURは無条件勝利
        if cpuCard.isSpecial { return false }   // (CPUは本来持たないはずだが保険として)
        if highWins {
            return playerCard.score > cpuCard.score
        } else {
            return playerCard.score < cpuCard.score
        }
    }
}
