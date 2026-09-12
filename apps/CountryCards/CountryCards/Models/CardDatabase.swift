import Foundation

/// cards.json のトップレベル構造(scripts/generate_cards.py が書き出す形と対応させる)。
private struct CardDataFile: Codable {
    let generatedAt: String
    let worldBankLastUpdated: String?
    let note: String
    let elements: [ElementMeta]
    let countries: [Country]
    let cards: [Card]
}

/// 要素ごとの「この要素で存在するカード総数」(図鑑の分母に使う)。
struct ElementMeta: Codable {
    let id: String
    let nameJa: String
    let unit: String
    let cardCount: Int
}

/// アプリに埋め込んだカードデータ(cards.json)を読み込み、画面から使いやすい
/// 形(国別・要素別など)に整理して持っておく置き場。
///
/// なぜ「読み込み専用データ」と「プレイヤーの所持状況」を分けているか:
/// カードの定義(どんなカードが存在するか)はアプリ更新でしか変わらないデータ、
/// 一方プレイヤーの所持状況は端末ごとに刻々と変わるデータ、と性質が違うため。
/// 混ぜてしまうと「新しいカードデータで上書きしたら所持記録も消えた」といった
/// 事故が起きやすくなる。所持状況は OwnedCollection が別途担当する。
@MainActor
final class CardDatabase: ObservableObject {
    static let shared = CardDatabase()

    let generatedAt: String
    let worldBankLastUpdated: String?
    let note: String
    let countries: [Country]
    let cards: [Card]

    private let countryByIso3: [String: Country]
    private let cardsByIso3: [String: [Card]]
    private let cardsByElement: [CardElement: [Card]]
    private let elementCardCount: [CardElement: Int]

    /// 北朝鮮のGDPカードのような特別カード(通常の要素別ランキングには出さない)。
    let specialCards: [Card]

    private init() {
        guard let url = Bundle.main.url(forResource: "cards", withExtension: "json") else {
            // アプリに同梱し忘れると即クラッシュするが、Phase 1時点では
            // 「カードデータが無い国カードバトルアプリ」は成立しないため、
            // 気づかずリリースしてしまうより早期に落として気づけるほうを選んだ。
            fatalError("cards.jsonが見つかりません。scripts/generate_cards.pyを実行し、"
                + "CountryCards/Resources/cards.json が生成されているか確認してください。")
        }

        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(CardDataFile.self, from: data)

            self.generatedAt = file.generatedAt
            self.worldBankLastUpdated = file.worldBankLastUpdated
            self.note = file.note
            self.countries = file.countries.sorted { $0.nameJa < $1.nameJa }
            self.cards = file.cards

            self.countryByIso3 = Dictionary(uniqueKeysWithValues: file.countries.map { ($0.iso3, $0) })

            var byIso3: [String: [Card]] = [:]
            var byElement: [CardElement: [Card]] = [:]
            var special: [Card] = []
            for card in file.cards {
                if card.isSpecial {
                    special.append(card)
                } else {
                    byIso3[card.iso3, default: []].append(card)
                    byElement[card.element, default: []].append(card)
                }
            }
            // 要素別ランキングはスコアが高い順(=珍しい・目立つ方が上)に並べておく。
            for key in byElement.keys {
                byElement[key]?.sort { $0.score > $1.score }
            }
            self.cardsByIso3 = byIso3
            self.cardsByElement = byElement
            self.specialCards = special

            var counts: [CardElement: Int] = [:]
            for meta in file.elements {
                if let element = CardElement(rawValue: meta.id) {
                    counts[element] = meta.cardCount
                }
            }
            self.elementCardCount = counts
        } catch {
            fatalError("cards.jsonの読み込みに失敗しました: \(error)")
        }
    }

    func country(for iso3: String) -> Country? {
        countryByIso3[iso3]
    }

    /// 指定した国が持ちうるカード一覧(通常カードのみ。特別カードは除く)。
    func cards(forCountry iso3: String) -> [Card] {
        cardsByIso3[iso3] ?? []
    }

    /// 指定した要素のランキング一覧(スコアの高い順)。
    func cards(forElement element: CardElement) -> [Card] {
        cardsByElement[element] ?? []
    }

    /// 「◯/◯枚」の分母(その要素・その国のカードが世界に何種類存在するか)。
    func totalCardCount(forElement element: CardElement) -> Int {
        elementCardCount[element] ?? 0
    }

    /// 全カード種類数(特別カードを含む)。図鑑トップのコンプリート率表示に使う。
    var totalCardCountIncludingSpecial: Int {
        cards.count + specialCards.count
    }
}
