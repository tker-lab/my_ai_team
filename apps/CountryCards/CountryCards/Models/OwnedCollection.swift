import Foundation

/// プレイヤーが実際に持っているカード・ポイントなどの「セーブデータ」。
///
/// 【永続化の暫定方針】今回はUserDefaultsに保存する(端末内だけで完結する、
/// もっとも手数の少ない方法)。app_team_country_cards.mdの決定事項にある
/// 「iCloud(Apple ID)に自動で紐付けて機種変更を引き継ぐ」は、無料Apple ID
/// (Personal Team)でiCloud機能(NSUbiquitousKeyValueStore等)がそのまま
/// 使えるか未確認のため、Phase 1では見送った【暫定判断】。Phase 2でiCloud対応
/// する際は、このクラスの保存先をUserDefaultsからiCloudのキー値ストアに
/// 差し替えるだけで済むよう、保存ロジックをこの1ファイルに閉じ込めてある。
@MainActor
final class OwnedCollection: ObservableObject {
    static let shared = OwnedCollection()

    private let defaults = UserDefaults.standard
    private let ownedCardIDsKey = "ownedCardIDs"
    private let dupePointsKey = "dupePoints"
    private let lastLoginBonusDateKey = "lastLoginBonusDate"
    private let firstLaunchDateKey = "firstLaunchDate"

    /// 持っているカードのID一覧("JPN_population"のような文字列)。
    @Published private(set) var ownedCardIDs: Set<String>

    /// ダブりカードのポイント(最大9999、10ポイントでガチャ1回分)。
    @Published private(set) var dupePoints: Int

    private init() {
        let saved = defaults.array(forKey: ownedCardIDsKey) as? [String] ?? []
        self.ownedCardIDs = Set(saved)
        self.dupePoints = defaults.integer(forKey: dupePointsKey)

        // 初回起動日を記録しておく(「初回ダウンロードから1週間だけ1日3回」の
        // ログインボーナス特典の判定に使う)。
        if defaults.object(forKey: firstLaunchDateKey) == nil {
            defaults.set(Date(), forKey: firstLaunchDateKey)
        }
    }

    var isOwned: (Card) -> Bool {
        { [ownedCardIDs] card in ownedCardIDs.contains(card.id) }
    }

    func owns(_ card: Card) -> Bool {
        ownedCardIDs.contains(card.id)
    }

    /// カードを1枚受け取る。すでに持っているカードなら「ダブり」としてポイント化する
    /// (app_team_country_cards.mdの「ダブりカードのポイント化」決定どおり)。
    /// 戻り値: 新規入手だったかどうか(演出の出し分け等に使える)。
    @discardableResult
    func receive(_ card: Card) -> Bool {
        if ownedCardIDs.contains(card.id) {
            dupePoints = min(dupePoints + 1, 9999)
            defaults.set(dupePoints, forKey: dupePointsKey)
            return false
        } else {
            ownedCardIDs.insert(card.id)
            defaults.set(Array(ownedCardIDs), forKey: ownedCardIDsKey)
            return true
        }
    }

    /// ダブりポイントを消費する(10pt=ガチャ1回、100pt=10回、1000pt=100回)。
    /// 足りなければfalseを返し、何も減らさない。
    func spendDupePoints(_ amount: Int) -> Bool {
        guard dupePoints >= amount else { return false }
        dupePoints -= amount
        defaults.set(dupePoints, forKey: dupePointsKey)
        return true
    }

    /// 指定した国について、何種類の要素カードを持っているか(豆知識の解放数に使う。Phase 2)。
    func ownedElementCount(forCountry iso3: String, among cards: [Card]) -> Int {
        cards.filter { $0.iso3 == iso3 && owns($0) }.count
    }

    // MARK: - デバッグ・開発用

    /// 開発中の動作確認のためにセーブデータを全消去する。本番導線には出さないこと。
    func resetForDebug() {
        ownedCardIDs = []
        dupePoints = 0
        defaults.removeObject(forKey: ownedCardIDsKey)
        defaults.removeObject(forKey: dupePointsKey)
    }
}
