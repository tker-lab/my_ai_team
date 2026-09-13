import Foundation

/// 対戦(CPU戦)1回分の進行を管理する。
///
/// ルール(app_team_country_cards.mdの決定事項どおり):
/// - 毎ターン「どの要素で比べるか」「高い方/低い方どちらが勝ちか」を両方ランダムに決める
/// - 【2026-09-13仕様変更】デッキ編成機能を廃止し、プレイヤーの手札もCPUと同じく
///   「持っているカードの中からランダムに出す」方式に統一した(手動でカードを
///   選ぶ操作自体が無くなった)。各要素で最低1枚を持ち続ける保証は
///   StartingCardsProvisioner(初回配布)が担う。
/// - CPUの手札は、要素ごとに1枚、そのターンごとにガチャと同じ確率でランダムに
///   抽選し直す(HUR無し・固定デッキではない)
/// - 北朝鮮GDPカード(HUR)はどのお題でも必ず勝つジョーカー
/// - 【2026-09-13追加】1試合5ターンの間、同じ要素を2回出題しない
///   (10要素中5要素を毎回変えて使う)
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
        /// 両者のカードはもう決まっているが、数値はまだ伏せてある
        /// (「対戦する」をタップすると決着が付く)。
        case ready(element: CardElement, highWins: Bool, playerCard: Card, cpuCard: Card)
        case revealing(round: Int)
        case finished
    }

    static let totalRounds = 5

    @Published private(set) var phase: Phase
    @Published private(set) var roundResults: [RoundResult] = []
    /// 対戦勝利によって無料ガチャが増えたかどうか(1日3回の上限に達していた場合はfalse)。
    @Published private(set) var wonFreeGachaBonus = false

    private let database: CardDatabase
    private let owned: OwnedCollection
    /// 1試合5ターンの間、同じ要素を2回出題しないための「使用済み要素」の記録。
    private var usedElements: Set<CardElement> = []

    var playerWinCount: Int { roundResults.filter(\.playerWon).count }
    var cpuWinCount: Int { roundResults.filter { !$0.playerWon }.count }
    var currentRoundNumber: Int { roundResults.count + 1 }

    init(database: CardDatabase, owned: OwnedCollection) {
        self.database = database
        self.owned = owned
        let element = Self.pickElement(excluding: [], database: database, owned: owned)
        self.usedElements = [element]
        let playerCard = Self.drawPlayerCard(for: element, database: database, owned: owned)
        let cpuCard = Self.drawCPUCard(for: element, database: database)
        self.phase = .ready(element: element, highWins: Bool.random(), playerCard: playerCard, cpuCard: cpuCard)
    }

    /// お題の要素を選ぶ。まだ出していない要素の中から、プレイヤーが実際に
    /// カードを持っている要素を優先して選ぶ(通常はStartingCardsProvisionerの
    /// 初回配布により、10要素全てで最低1枚は所持しているはずだが、念のための保険)。
    private static func pickElement(excluding usedElements: Set<CardElement>, database: CardDatabase, owned: OwnedCollection) -> CardElement {
        let remaining = CardElement.allCases.filter { !usedElements.contains($0) }
        let withOwnedCards = remaining.filter { hasOwnedCard(for: $0, database: database, owned: owned) }
        return withOwnedCards.randomElement() ?? remaining.randomElement() ?? CardElement.allCases.randomElement()!
    }

    private static func hasOwnedCard(for element: CardElement, database: CardDatabase, owned: OwnedCollection) -> Bool {
        ownedCardPool(for: element, database: database, owned: owned).isEmpty == false
    }

    /// 指定した要素で、プレイヤーが実際に持っているカードの一覧
    /// (特別カード=北朝鮮GDPを持っていれば、それもGDP要素の候補に含める)。
    private static func ownedCardPool(for element: CardElement, database: CardDatabase, owned: OwnedCollection) -> [Card] {
        let all = database.cards(forElement: element) + database.specialCards.filter { $0.element == element }
        return all.filter(owned.owns)
    }

    /// プレイヤーの手札は「持っているカードの中からランダムに出す」(決定事項どおり、
    /// CPUと同じ方式)。StartingCardsProvisionerの保証により候補が空になることは
    /// 無いはずだが、万一空だった場合は進行不能を避けるため、ガチャと同じ確率で
    /// その場で1枚引いた扱いにする(所持はしていない一時的なカードとして使うのみ)。
    private static func drawPlayerCard(for element: CardElement, database: CardDatabase, owned: OwnedCollection) -> Card {
        let candidates = ownedCardPool(for: element, database: database, owned: owned)
        if let picked = candidates.randomElement() {
            return picked
        }
        return drawCPUCard(for: element, database: database)
    }

    /// カードは決まっているが数値は伏せてある状態から、決着を付けて公開する。
    func revealBattle() {
        guard case .ready(let element, let highWins, let playerCard, let cpuCard) = phase else { return }

        let playerWon = Self.resolveWinner(playerCard: playerCard, cpuCard: cpuCard, highWins: highWins)
        roundResults.append(RoundResult(
            element: element, highWins: highWins,
            playerCard: playerCard, cpuCard: cpuCard, playerWon: playerWon
        ))
        phase = .revealing(round: roundResults.count)
    }

    /// 火花演出(+数値公開)を見終わったら次のターンへ(または対戦終了へ)進む。
    func proceedAfterReveal() {
        guard case .revealing = phase else { return }
        if roundResults.count >= Self.totalRounds {
            finish()
            return
        }
        let element = Self.pickElement(excluding: usedElements, database: database, owned: owned)
        usedElements.insert(element)
        let playerCard = Self.drawPlayerCard(for: element, database: database, owned: owned)
        let cpuCard = Self.drawCPUCard(for: element, database: database)
        phase = .ready(element: element, highWins: Bool.random(), playerCard: playerCard, cpuCard: cpuCard)
    }

    private func finish() {
        phase = .finished
        if playerWinCount > cpuWinCount {
            owned.recordBattleWin()
            // 決定事項どおり「対戦の勝利:1日3回まで」ガチャが増える
            // (4勝目以降も対戦自体は何度でもできるが、ガチャは増えない)。
            wonFreeGachaBonus = DailyBonusManager.shared.claimBattleBonus()
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
