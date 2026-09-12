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
    private let usernameKey = "username"
    private let battleWinCountKey = "battleWinCount"
    private let gachaUseCountKey = "gachaUseCount"
    private let completionDateKey = "completionDate"

    /// 持っているカードのID一覧("JPN_population"のような文字列)。
    @Published private(set) var ownedCardIDs: Set<String>

    /// ダブりカードのポイント(最大9999、10ポイントでガチャ1回分)。
    @Published private(set) var dupePoints: Int

    /// プロフィール画面に出すユーザー名(未登録ならnil)。
    @Published private(set) var username: String?

    /// 対戦の累計勝利数(1日でリセットされない、ずっと積み上がる記録)。
    @Published private(set) var battleWinCount: Int

    /// ガチャの累計使用回数(3枚出る1回引き=1回とカウント。10連なら+10)。
    @Published private(set) var gachaUseCount: Int

    /// 全カードをコンプリートした日時(未達成ならnil)。全国ランキング(所持枚数)で
    /// 「コンプリート済み同士は達成が早い人ほど上位」を実現するために使う
    /// (詳細はGameCenterManagerのスコア計算を参照)。
    @Published private(set) var completionDate: Date?

    private init() {
        let saved = defaults.array(forKey: ownedCardIDsKey) as? [String] ?? []
        self.ownedCardIDs = Set(saved)
        self.dupePoints = defaults.integer(forKey: dupePointsKey)
        self.username = defaults.string(forKey: usernameKey)
        self.battleWinCount = defaults.integer(forKey: battleWinCountKey)
        self.gachaUseCount = defaults.integer(forKey: gachaUseCountKey)
        self.completionDate = defaults.object(forKey: completionDateKey) as? Date

        // 初回起動日を記録しておく(「初回ダウンロードから1週間だけ1日3回」の
        // ログインボーナス特典の判定に使う)。
        if defaults.object(forKey: firstLaunchDateKey) == nil {
            defaults.set(Date(), forKey: firstLaunchDateKey)
        }
    }

    /// 何種類のカードを持っているか(ダブりを除いたユニークな枚数)。
    /// プロフィールの王冠アイコンの色分けに使う。
    var uniqueCardCount: Int { ownedCardIDs.count }

    /// まだコンプリート日時を記録していなければ、今のカード数が実際の総数に
    /// 達した瞬間の日時を1回だけ記録する(2回目以降は何もしない=最初に
    /// 達成した日時が上書きされないようにする)。
    func noteCompletionIfNeeded(totalCardCount: Int) {
        guard completionDate == nil, totalCardCount > 0, uniqueCardCount >= totalCardCount else { return }
        let now = Date()
        completionDate = now
        defaults.set(now, forKey: completionDateKey)
    }

    func updateUsername(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        username = trimmed.isEmpty ? nil : trimmed
        defaults.set(username, forKey: usernameKey)
    }

    func recordBattleWin() {
        battleWinCount += 1
        defaults.set(battleWinCount, forKey: battleWinCountKey)
    }

    /// 対戦に勝った時の簡易報酬(ダブりポイントを付与)。
    /// 【暫定判断】「対戦の勝利:1日3回まで、ガチャが引ける」という決定事項の
    /// 本格的な実装(1日の回数管理を含む共通のガチャ入手手段のまとめ)はPhase 2に
    /// 回し、今回は「勝つとポイントが少し貯まる」という簡易な形にしている。
    @discardableResult
    func receiveBattleWinBonus(points: Int = 5) -> Int {
        dupePoints = min(dupePoints + points, 9999)
        defaults.set(dupePoints, forKey: dupePointsKey)
        return dupePoints
    }

    /// ガチャを引くたびに呼ぶ。`pullCount`は「3枚出る1回引き」を何回分引いたか
    /// (単発なら1、10連なら10、100連なら100)。
    func recordGachaUse(pullCount: Int) {
        gachaUseCount += pullCount
        defaults.set(gachaUseCount, forKey: gachaUseCountKey)
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
        battleWinCount = 0
        gachaUseCount = 0
        completionDate = nil
        defaults.removeObject(forKey: ownedCardIDsKey)
        defaults.removeObject(forKey: dupePointsKey)
        defaults.removeObject(forKey: battleWinCountKey)
        defaults.removeObject(forKey: gachaUseCountKey)
        defaults.removeObject(forKey: completionDateKey)
    }
}
