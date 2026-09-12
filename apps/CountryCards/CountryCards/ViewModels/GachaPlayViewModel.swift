import Foundation

/// ガチャ1回分の演出の進み方を管理するViewModel。
///
/// app_team_country_cards.mdで決まった「通常モード」「スキップモード」の
/// 分岐をこのクラスの状態遷移として実装している。演出の作り込み(映像の
/// クオリティ等)はPhase 2に回し、今回はこの2モードの分岐が正しく動くことを
/// 最優先にした。
@MainActor
final class GachaPlayViewModel: ObservableObject {
    /// 画面がいまどの段階にあるか。
    enum Phase: Equatable {
        /// 通常モード:導入演出が画面に出ているが、タップするまで動かない。
        case introPaused
        /// タップ後、導入演出が再生されている(この段階でもスキップは押せる)。
        case introPlaying
        /// index番目のカードを表示中。faceUpがtrueなら中身が見えている状態。
        case revealing(index: Int, faceUp: Bool)
        /// 3枚とも見終わった。
        case done
    }

    let element: CardElement
    @Published private(set) var phase: Phase = .introPaused
    @Published private(set) var pullResult: GachaPullResult?
    @Published private(set) var isSkipMode = false
    /// このカードは今回初めて手に入れた(true)か、ダブり(false)か。
    /// 演出上の「新規入手!」表示に使う。
    @Published private(set) var isNewByIndex: [Bool] = []

    private let engine: GachaEngine
    private let owned: OwnedCollection

    init(element: CardElement, database: CardDatabase, owned: OwnedCollection) {
        self.element = element
        self.owned = owned
        let cardsForElement = database.cards(forElement: element)
        // 北朝鮮のGDPカード(特別カード)は、要素がGDPの時だけ抽選対象に含める。
        let special = element == .gdp ? database.specialCards.first(where: { $0.element == .gdp }) : nil
        self.engine = GachaEngine(cardsForElement: cardsForElement, specialCard: special)
    }

    /// ガチャを1回(3枚)引いて、演出を最初からやり直す。
    func startPull() {
        let result = engine.drawOnePull()
        pullResult = result
        isNewByIndex = Array(repeating: false, count: result.cards.count)
        isSkipMode = false
        phase = .introPaused
    }

    /// 導入演出エリアをタップ(通常モード開始のトリガー)。
    func tapIntro() {
        guard phase == .introPaused else { return }
        phase = .introPlaying
        Task {
            // 本来は動画・パーティクル演出の再生時間。Phase 1では簡易な待ち時間で代用する。
            try? await Task.sleep(for: .seconds(1.2))
            guard self.phase == .introPlaying else { return } // その間にスキップされていたら何もしない
            self.phase = .revealing(index: 0, faceUp: false)
        }
    }

    /// スキップボタン。導入演出を飛ばし、N/SRは自動でめくり、SSR以上で止まる。
    func tapSkip() {
        guard phase == .introPaused || phase == .introPlaying else { return }
        isSkipMode = true
        revealAndAutoAdvance(index: 0)
    }

    /// カード表示エリアをタップした時の処理。状況によって
    /// 「カードを表にする」「次のカードへ進む」のどちらかが起きる。
    func tapCard() {
        guard case .revealing(let index, let faceUp) = phase else { return }
        if !faceUp {
            // 通常モードで、まだ裏向きのカードをタップして表にする。
            revealCard(at: index)
            phase = .revealing(index: index, faceUp: true)
        } else if isSkipMode {
            revealAndAutoAdvance(index: index + 1)
        } else {
            advanceManually(to: index + 1)
        }
    }

    // MARK: - 内部処理

    private func revealCard(at index: Int) {
        guard let pullResult, index < pullResult.cards.count else { return }
        let card = pullResult.cards[index]
        let isNew = owned.receive(card)
        if isNewByIndex.indices.contains(index) {
            isNewByIndex[index] = isNew
        }
    }

    private func advanceManually(to index: Int) {
        guard let pullResult, index < pullResult.cards.count else {
            phase = .done
            return
        }
        phase = .revealing(index: index, faceUp: false)
    }

    /// スキップモード用:カードを即座に表にし、N/SRなら少し待って自動的に次へ進む。
    /// SSR以上(北朝鮮GDPのHURを含む)は必ずここで止まり、tapCard()を待つ
    /// (「SSR以上は必ずタップさせて溜めを作る」という決定事項どおり)。
    private func revealAndAutoAdvance(index: Int) {
        guard let pullResult, index < pullResult.cards.count else {
            phase = .done
            return
        }
        let card = pullResult.cards[index]
        revealCard(at: index)
        phase = .revealing(index: index, faceUp: true)

        if card.rarity < .ssr {
            Task {
                try? await Task.sleep(for: .seconds(0.6))
                // 待っている間に3枚目まで進んで終了していないかを確認してから続ける。
                guard self.isSkipMode, case .revealing(let currentIndex, true) = self.phase,
                      currentIndex == index else { return }
                self.revealAndAutoAdvance(index: index + 1)
            }
        }
        // SSR以上の場合はここで何もしない = 画面はタップ待ちのまま止まる。
    }
}
