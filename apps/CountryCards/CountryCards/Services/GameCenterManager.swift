import GameKit
import SwiftUI

/// 全国ランキング(所持枚数・対戦累計勝利数・ガチャ累計回数)をGame Centerで
/// 実現するための窓口。
///
/// 【重要な注意・実装状況】Game Centerの実際のランキングにスコアを送るには、
/// ①Apple Developer PortalでこのアプリのApp IDに「Game Center」機能を
/// 有効にする ②App Store Connectでこの3つのリーダーボードID
/// (leaderboardID定数を参照)を実際に作成する、という2つの手続きが別途必要。
/// どちらもApple Developer Portal/App Store ConnectへのWebブラウザでの
/// ログイン操作が要り、この開発環境(Claude Code)からは実行できないため、
/// **今回はコード側の実装のみ**で、実際にサーバーへスコアが届くところまでは
/// 未確認。CEOが上記2つの手続きを行った後、実機かシミュレータでGame Centerに
/// サインインした状態でガチャ・対戦を行えば動作確認できる想定。
@MainActor
final class GameCenterManager: ObservableObject {
    static let shared = GameCenterManager()

    /// 3つのランキングのID。App Store Connect側でも必ずこの文字列と
    /// 完全に一致するリーダーボードを作成すること。
    enum LeaderboardID: String {
        case cardCount = "com.aiteam.countrycards.leaderboard.cardcount"
        case battleWins = "com.aiteam.countrycards.leaderboard.battlewins"
        case gachaCount = "com.aiteam.countrycards.leaderboard.gachacount"
    }

    /// 所持枚数リーダーボードの「コンプリート達成者」を、通常の枚数(最大でも
    /// 総カード数程度)より必ず上位にするための下駄(ベースとなる大きな数)。
    /// Unix時刻(秒)を引いた値をスコアにすることで「達成が早いほど加点」を
    /// 実現する(CEO決定のアイデアそのまま)。カード総数が将来増えても
    /// 余裕を持って上回れるよう、実際の総数よりずっと大きい数を使う。
    static let completionScoreBase: Int = 3_000_000_000

    @Published private(set) var isAuthenticated = false
    @Published private(set) var authenticationError: String?

    private init() {}

    /// アプリ起動時に一度呼ぶ。サインインしていなければ、システムが自動で
    /// サインイン画面を出してくれる(GKLocalPlayerの仕組み)。
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                if let viewController {
                    // サインインが必要な時、システムから渡される画面を
                    // 一番手前のウィンドウに表示する。
                    Self.present(viewController)
                    return
                }
                if let error {
                    self?.authenticationError = error.localizedDescription
                    self?.isAuthenticated = false
                    return
                }
                self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            }
        }
    }

    private static func present(_ viewController: UIViewController) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        root.present(viewController, animated: true)
    }

    /// 所持枚数を送信する。コンプリート済みなら「最大値+早さボーナス」の
    /// スコアに変換してから送る(表示側=LeaderboardViewが元の意味に読み替える)。
    func submitCardCountScore(owned: OwnedCollection, totalCardCount: Int) {
        owned.noteCompletionIfNeeded(totalCardCount: totalCardCount)
        let score: Int
        if let completionDate = owned.completionDate {
            let secondsSinceEpoch = Int(completionDate.timeIntervalSince1970)
            score = Self.completionScoreBase - secondsSinceEpoch
        } else {
            score = owned.uniqueCardCount
        }
        submit(score: score, to: .cardCount)
    }

    func submitBattleWinScore(_ count: Int) {
        submit(score: count, to: .battleWins)
    }

    func submitGachaCountScore(_ count: Int) {
        submit(score: count, to: .gachaCount)
    }

    /// 3つのランキングを一括で最新の値に送り直す。ガチャを引いた後・対戦に
    /// 勝った後など、記録が変わったタイミングで呼べば十分な設計にしてある。
    func syncAllScores(owned: OwnedCollection, database: CardDatabase) {
        submitCardCountScore(owned: owned, totalCardCount: database.totalCardCountIncludingSpecial)
        submitBattleWinScore(owned.battleWinCount)
        submitGachaCountScore(owned.gachaUseCount)
    }

    private func submit(score: Int, to leaderboard: LeaderboardID) {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        Task {
            do {
                try await GKLeaderboard.submitScore(
                    score,
                    context: 0,
                    player: GKLocalPlayer.local,
                    leaderboardIDs: [leaderboard.rawValue]
                )
            } catch {
                // ランキング送信の失敗はゲーム進行自体には影響させない
                // (通信が無い・未対応環境などで落ちないようにするため)。
                print("[GameCenter] スコア送信に失敗: \(leaderboard.rawValue) \(error)")
            }
        }
    }

    /// 上位ランキングを読み込む(表示用)。
    func loadTopEntries(for leaderboard: LeaderboardID, count: Int = 20) async -> [GKLeaderboard.Entry] {
        guard GKLocalPlayer.local.isAuthenticated else { return [] }
        do {
            let leaderboards = try await GKLeaderboard.loadLeaderboards(IDs: [leaderboard.rawValue])
            guard let board = leaderboards.first else { return [] }
            let (_, entries, _) = try await board.loadEntries(
                for: .global,
                timeScope: .allTime,
                range: NSRange(location: 1, length: count)
            )
            return entries
        } catch {
            print("[GameCenter] ランキング取得に失敗: \(leaderboard.rawValue) \(error)")
            return []
        }
    }
}
