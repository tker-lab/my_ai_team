import Foundation

/// 対戦(CPU戦)1回分の進行を管理する。
///
/// ルール(app_team_country_cards.mdの決定事項どおり):
/// - 毎ターン「どの要素で比べるか」「高い方/低い方どちらが勝ちか」を両方ランダムに決める
/// - 【2026-09-14仕様変更】「持っているカードから自動でランダムに1枚出す」方式を廃止し、
///   以下の選択式フローに変更した:
///   1. お題(要素・高低)が決まると、CPU側のカードを1枚(国・要素は見える、数値は「?」)
///      先に提示する
///   2. プレイヤーには、その要素で持っているカードの中から4枚(数値は「?」)を提示し、
///      タップして1枚選ばせる(初回配布で各要素5枚Nレアを持っているため4枚に満たない
///      状況は起きない設計)
///   3. プレイヤーが選ぶと、両者の数値をまとめて公開して勝敗を決める
///   これにより「相手の顔ぶれを見てから自分の手札のどれを出すか選ぶ」駆け引きを持たせる。
///   各要素で最低1枚を持ち続ける保証は StartingCardsProvisioner(初回配布)が担う。
/// - CPUの手札は、要素ごとに1枚、そのターンごとにガチャと同じ確率でランダムに
///   抽選し直す(HUR無し・固定デッキではない)
/// - 北朝鮮GDPカード(HUR)はどのお題でも必ず勝つジョーカー
/// - 1試合5ターンの間、同じ要素を2回出題しない(10要素中5要素を毎回変えて使う)
/// - 【暫定判断】対戦の決着方法(何ターンで勝敗を決めるか)は決定事項に無かったため、
///   5ターン中、勝ちが多い方が対戦の勝者、という分かりやすい形にした
/// - 【暫定判断】5枚以上持っている場合にプレイヤーへ見せる4枚の選び方は、決定事項が
///   「部署に一任」としていたため、毎回ランダムな4枚を選ぶ方式にした
/// - 【2026-09-14 実機フィードバック修正】数値が同じ時は「引き分け」にする(以前は
///   `>` / `<` の比較しか無く、同値が誤って「負け」扱いになるバグがあった)。
///   5ターン終えた結果、勝ち数が同じ(試合トータルが引き分け)になるのもそのまま
///   許容し、無理に決着を付ける処理は追加しない。
/// - 【2026-09-14 実機フィードバック修正】決着後は選んだ1枚とCPUのカードだけでなく、
///   その場に提示されていた4枚全部(選ばなかった3枚も含む)の数値を公開する。
///   そのため RoundResult には候補4枚(candidates)も保持しておく。
@MainActor
final class BattleViewModel: ObservableObject {
    /// 1ターンの決着結果。「引き分け」を独立したケースとして持つ(Boolの勝敗フラグだと
    /// 同値の扱いが「勝ち」「負け」のどちらかに寄ってしまい、上記のバグの原因になった)。
    enum RoundOutcome: Equatable {
        case playerWin
        case cpuWin
        case draw
    }

    struct RoundResult: Identifiable {
        let id = UUID()
        let element: CardElement
        let highWins: Bool
        let playerCard: Card
        let cpuCard: Card
        let outcome: RoundOutcome
        /// その場に提示されていた候補4枚(選んだ1枚を含む)。決着後にまとめて
        /// 全部の数値を公開するために保持する。
        let candidates: [Card]
    }

    enum Phase: Equatable {
        /// お題とCPUのカードは決まっており、プレイヤーが4枚の候補から1枚を選ぶのを待っている状態。
        /// 両者の数値は選び終わるまで伏せたまま。
        case choosing(element: CardElement, highWins: Bool, cpuCard: Card, candidates: [Card])
        case revealing(round: Int)
        case finished
    }

    static let totalRounds = 5
    /// プレイヤーに提示する候補カードの枚数。
    static let candidateCount = 4

    @Published private(set) var phase: Phase
    @Published private(set) var roundResults: [RoundResult] = []
    /// 対戦勝利によって無料ガチャが増えたかどうか(1日3回の上限に達していた場合はfalse)。
    @Published private(set) var wonFreeGachaBonus = false

    private let database: CardDatabase
    private let owned: OwnedCollection
    /// 1試合5ターンの間、同じ要素を2回出題しないための「使用済み要素」の記録。
    private var usedElements: Set<CardElement> = []

    var playerWinCount: Int { roundResults.filter { $0.outcome == .playerWin }.count }
    var cpuWinCount: Int { roundResults.filter { $0.outcome == .cpuWin }.count }
    var drawCount: Int { roundResults.filter { $0.outcome == .draw }.count }
    var currentRoundNumber: Int { roundResults.count + 1 }

    init(database: CardDatabase, owned: OwnedCollection) {
        self.database = database
        self.owned = owned
        let element = Self.pickElement(excluding: [], database: database, owned: owned)
        self.usedElements = [element]
        let cpuCard = Self.drawCPUCard(for: element, database: database)
        let candidates = Self.pickPlayerCandidates(for: element, database: database, owned: owned)
        self.phase = .choosing(element: element, highWins: Bool.random(), cpuCard: cpuCard, candidates: candidates)
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

    /// プレイヤーに提示する候補カード(その要素で持っているカードからランダムに
    /// candidateCount枚)。StartingCardsProvisionerの保証により通常は5枚以上
    /// 持っているはずだが、万一足りない場合は進行不能を避けるため、ガチャと
    /// 同じ確率でその場で引いた(所持はしていない一時的な)カードで埋める。
    private static func pickPlayerCandidates(for element: CardElement, database: CardDatabase, owned: OwnedCollection) -> [Card] {
        var pool = ownedCardPool(for: element, database: database, owned: owned).shuffled()
        if pool.count > candidateCount {
            pool = Array(pool.prefix(candidateCount))
        }
        while pool.count < candidateCount {
            pool.append(drawCPUCard(for: element, database: database))
        }
        return pool
    }

    /// プレイヤーが4枚の候補から1枚を選んだ時に呼ぶ。両者の数値をまとめて
    /// 公開し、決着を付ける。
    func choosePlayerCard(_ card: Card) {
        guard case .choosing(let element, let highWins, let cpuCard, let candidates) = phase,
              candidates.contains(where: { $0.id == card.id }) else { return }

        let outcome = Self.resolveOutcome(playerCard: card, cpuCard: cpuCard, highWins: highWins)
        roundResults.append(RoundResult(
            element: element, highWins: highWins,
            playerCard: card, cpuCard: cpuCard, outcome: outcome, candidates: candidates
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
        let cpuCard = Self.drawCPUCard(for: element, database: database)
        let candidates = Self.pickPlayerCandidates(for: element, database: database, owned: owned)
        phase = .choosing(element: element, highWins: Bool.random(), cpuCard: cpuCard, candidates: candidates)
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
        // playerWinCount == cpuWinCount の場合(試合トータルが引き分け)は、勝利報酬も
        // 敗北時の処理も無く、そのまま「引き分け」として終える(2026-09-14決定:
        // 無理に決着を付ける処理は追加しない)。
    }

    /// CPUの手札をその場で抽選する(HURは除外。決定事項どおり)。
    private static func drawCPUCard(for element: CardElement, database: CardDatabase) -> Card {
        let cardsForElement = database.cards(forElement: element)
        let engine = GachaEngine(cardsForElement: cardsForElement, specialCard: nil)
        return engine.drawSingleCardForCPU()
    }

    /// 勝敗判定。北朝鮮GDPカード(HUR)はどちらの向きでも必ず勝つ。
    /// 【2026-09-14修正】以前は `>` / `<` の比較結果をそのままBoolにしていたため、
    /// 両者の数値が同じ場合(公用語の数など小さい整数で同値になりやすい要素)に
    /// `false` = 「プレイヤーの負け」と誤判定されるバグがあった。同値は明示的に
    /// `.draw` として扱う。
    private static func resolveOutcome(playerCard: Card, cpuCard: Card, highWins: Bool) -> RoundOutcome {
        if playerCard.isSpecial { return .playerWin } // HURは無条件勝利
        if cpuCard.isSpecial { return .cpuWin }       // (CPUは本来持たないはずだが保険として)
        if playerCard.score == cpuCard.score { return .draw }
        if highWins {
            return playerCard.score > cpuCard.score ? .playerWin : .cpuWin
        } else {
            return playerCard.score < cpuCard.score ? .playerWin : .cpuWin
        }
    }
}
