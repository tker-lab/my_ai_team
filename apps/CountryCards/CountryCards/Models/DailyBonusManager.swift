import Foundation

/// 「無料でガチャを引ける回数」の管理役。
///
/// チェック工程で指摘された不具合(2026-09-13)への対応:従来はこのクラスが
/// 存在せず、通常ガチャ(GachaPlayView)がボタンを押すたびに無制限に引けて
/// しまっていた。app_team_country_cards.mdの決定事項どおり、
/// ①ログインボーナス(1日1回。初回ダウンロードから1週間だけ1日3回)
/// ②広告視聴(1日3回まで。広告SDK自体は未組み込みのため、視聴完了ボタンで代用)
/// ③対戦の勝利(1日3回まで)
/// の3つの手段だけが「無料で引ける回数」を増やせるようにし、それ以外の場面
/// (通常ガチャの「もう一度引く」等)では回数を消費するだけで増やさない。
///
/// 「1日」の境目はCalendar.current.startOfDay(端末のカレンダー日付)で判定する。
@MainActor
final class DailyBonusManager: ObservableObject {
    static let shared = DailyBonusManager()

    private let defaults = UserDefaults.standard
    private let freePullsKey = "freePullsAvailable"
    private let firstLaunchDateKey = "firstLaunchDate" // OwnedCollectionと同じキーを共有する
    private let lastLoginGrantDayKey = "lastLoginGrantDay"
    private let adBonusDayKey = "adBonusDay"
    private let adBonusCountKey = "adBonusCountToday"
    private let battleBonusDayKey = "battleBonusDay"
    private let battleBonusCountKey = "battleBonusCountToday"

    static let maxAdBonusPerDay = 3
    static let maxBattleBonusPerDay = 3
    /// 通常時のログインボーナス(1日1回)。初回ダウンロードから7日間はこの倍数を使う。
    static let normalLoginBonusPerDay = 1
    static let firstWeekLoginBonusPerDay = 3
    static let firstWeekDurationInDays = 7

    /// 今引ける無料ガチャの残り回数(1回=3枚のガチャ1回ぶん)。
    @Published private(set) var freePullsAvailable: Int
    @Published private(set) var adBonusRemainingToday: Int
    @Published private(set) var battleBonusRemainingToday: Int
    /// 今日ログインボーナスを受け取った直後だけtrueにする一時フラグ(通知表示用)。
    @Published var justGrantedLoginBonus: Int?

    private init() {
        freePullsAvailable = defaults.integer(forKey: freePullsKey)
        adBonusRemainingToday = Self.maxAdBonusPerDay
        battleBonusRemainingToday = Self.maxBattleBonusPerDay

        if defaults.object(forKey: firstLaunchDateKey) == nil {
            defaults.set(Date(), forKey: firstLaunchDateKey)
        }

        rolloverAdIfNeeded()
        rolloverBattleIfNeeded()
        grantLoginBonusIfNeeded()
    }

    private func startOfToday() -> Date { Calendar.current.startOfDay(for: Date()) }

    private func addFreePulls(_ amount: Int) {
        freePullsAvailable += amount
        defaults.set(freePullsAvailable, forKey: freePullsKey)
    }

    // MARK: - ログインボーナス(1日1回、初回から1週間だけ1日3回)

    private func grantLoginBonusIfNeeded() {
        let today = startOfToday()
        if let storedDay = defaults.object(forKey: lastLoginGrantDayKey) as? Date, storedDay == today {
            return // 今日はすでに受け取り済み
        }
        defaults.set(today, forKey: lastLoginGrantDayKey)

        let firstLaunch = (defaults.object(forKey: firstLaunchDateKey) as? Date) ?? today
        let daysSinceFirstLaunch = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: firstLaunch), to: today
        ).day ?? 0
        let amount = daysSinceFirstLaunch < Self.firstWeekDurationInDays
            ? Self.firstWeekLoginBonusPerDay
            : Self.normalLoginBonusPerDay
        addFreePulls(amount)
        justGrantedLoginBonus = amount
    }

    // MARK: - 広告視聴ボーナス(1日3回まで)

    private func rolloverAdIfNeeded() {
        let today = startOfToday()
        if let storedDay = defaults.object(forKey: adBonusDayKey) as? Date, storedDay == today {
            adBonusRemainingToday = Self.maxAdBonusPerDay - defaults.integer(forKey: adBonusCountKey)
        } else {
            defaults.set(today, forKey: adBonusDayKey)
            defaults.set(0, forKey: adBonusCountKey)
            adBonusRemainingToday = Self.maxAdBonusPerDay
        }
    }

    /// 広告を見終わった時に呼ぶ。1日3回まで無料ガチャが1回増える。
    /// 【実装状況】広告SDK自体はPhase 2で未組み込みのため、このメソッドは
    /// 「視聴完了」をその場でシミュレートするボタンから呼ばれる。
    @discardableResult
    func claimAdBonus() -> Bool {
        rolloverAdIfNeeded()
        guard adBonusRemainingToday > 0 else { return false }
        defaults.set(defaults.integer(forKey: adBonusCountKey) + 1, forKey: adBonusCountKey)
        adBonusRemainingToday -= 1
        addFreePulls(1)
        return true
    }

    // MARK: - 対戦勝利ボーナス(1日3回まで)

    private func rolloverBattleIfNeeded() {
        let today = startOfToday()
        if let storedDay = defaults.object(forKey: battleBonusDayKey) as? Date, storedDay == today {
            battleBonusRemainingToday = Self.maxBattleBonusPerDay - defaults.integer(forKey: battleBonusCountKey)
        } else {
            defaults.set(today, forKey: battleBonusDayKey)
            defaults.set(0, forKey: battleBonusCountKey)
            battleBonusRemainingToday = Self.maxBattleBonusPerDay
        }
    }

    /// 対戦に勝った時に呼ぶ。4勝目以降(1日)は呼んでもfalseを返すだけで増えない
    /// (「体力・スタミナのような制限は設けない」= 対戦自体は何度でもできる、という
    /// 決定事項どおり、対戦回数は制限しない。増えないのはガチャ回数だけ)。
    @discardableResult
    func claimBattleBonus() -> Bool {
        rolloverBattleIfNeeded()
        guard battleBonusRemainingToday > 0 else { return false }
        defaults.set(defaults.integer(forKey: battleBonusCountKey) + 1, forKey: battleBonusCountKey)
        battleBonusRemainingToday -= 1
        addFreePulls(1)
        return true
    }

    // MARK: - 消費

    /// 無料ガチャを1回消費する。残りが無ければfalseを返し、何も減らさない。
    @discardableResult
    func consumeFreePull() -> Bool {
        guard freePullsAvailable > 0 else { return false }
        freePullsAvailable -= 1
        defaults.set(freePullsAvailable, forKey: freePullsKey)
        return true
    }

    // MARK: - デバッグ・開発用

    func resetForDebug() {
        freePullsAvailable = 0
        adBonusRemainingToday = Self.maxAdBonusPerDay
        battleBonusRemainingToday = Self.maxBattleBonusPerDay
        defaults.removeObject(forKey: freePullsKey)
        defaults.removeObject(forKey: lastLoginGrantDayKey)
        defaults.removeObject(forKey: adBonusDayKey)
        defaults.removeObject(forKey: adBonusCountKey)
        defaults.removeObject(forKey: battleBonusDayKey)
        defaults.removeObject(forKey: battleBonusCountKey)
    }
}
