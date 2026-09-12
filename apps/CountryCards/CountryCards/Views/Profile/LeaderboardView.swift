import GameKit
import SwiftUI

/// 全国ランキング画面。所持枚数・対戦累計勝利数・ガチャ累計回数の3つを見せる。
///
/// 【動作状況の注意】Game Center側の設定(App ID機能の有効化・リーダーボード
/// の作成)がまだの間は、この画面はずっと「Game Centerにサインインしてください」
/// または「まだ誰もランキングに登録されていません」という表示のままになる。
/// これはコードの不具合ではなく、Apple Developer Portal側の設定待ちの状態。
/// 詳細はGameCenterManagerのコメントと完了報告を参照。
struct LeaderboardView: View {
    private enum Board: String, CaseIterable, Identifiable {
        case cardCount = "所持枚数"
        case battleWins = "対戦勝利数"
        case gachaCount = "ガチャ回数"
        var id: String { rawValue }

        var leaderboardID: GameCenterManager.LeaderboardID {
            switch self {
            case .cardCount: return .cardCount
            case .battleWins: return .battleWins
            case .gachaCount: return .gachaCount
            }
        }
    }

    @ObservedObject private var gameCenter = GameCenterManager.shared
    @State private var selectedBoard: Board = .cardCount
    @State private var entries: [GKLeaderboard.Entry] = []
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("ランキング", selection: $selectedBoard) {
                ForEach(Board.allCases) { board in
                    Text(board.rawValue).tag(board)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if !gameCenter.isAuthenticated {
                ContentUnavailableFallback(
                    title: "Game Centerにサインインしてください",
                    message: "全国ランキングに参加するには、端末の設定でGame Centerにサインインしている必要があります。"
                )
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                ContentUnavailableFallback(
                    title: "まだ記録がありません",
                    message: "ガチャを引いたり対戦したりすると、ここにランキングが表示されます。"
                )
            } else {
                List(entries, id: \.player.gamePlayerID) { entry in
                    HStack {
                        Text("\(entry.rank)位")
                            .font(.subheadline.bold())
                            .frame(width: 50, alignment: .leading)
                        Text(entry.player.displayName)
                        Spacer()
                        Text(displayValue(for: entry, board: selectedBoard))
                            .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("全国ランキング")
        .task(id: selectedBoard) {
            await reload()
        }
    }

    private func reload() async {
        guard gameCenter.isAuthenticated else { return }
        isLoading = true
        entries = await gameCenter.loadTopEntries(for: selectedBoard.leaderboardID)
        isLoading = false
    }

    /// 所持枚数ランキングだけ、コンプリート勢のスコア(下駄が乗った大きな数)を
    /// 「コンプリート(達成日)」の表示に読み替える(決定事項どおり)。
    private func displayValue(for entry: GKLeaderboard.Entry, board: Board) -> String {
        guard board == .cardCount else {
            return "\(entry.score)"
        }
        // 通常の所持枚数は多くても数千枚程度なので、それよりずっと大きい値なら
        // 「コンプリート達成による下駄乗せスコア」と判断できる。
        if entry.score > 100_000_000 {
            // completionScoreBase(30億)から実際の達成秒数を引いた値がスコアなので、
            // 引き算で元のUnix時刻に戻す。
            let secondsSinceEpoch = GameCenterManager.completionScoreBase - entry.score
            let date = Date(timeIntervalSince1970: TimeInterval(secondsSinceEpoch))
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy年M月d日"
            return "コンプリート(\(formatter.string(from: date))達成)"
        }
        return "\(entry.score)枚"
    }
}

/// iOS17未満でも動くよう、標準のContentUnavailableViewは使わず自前で用意した
/// シンプルな「空の状態」表示。
private struct ContentUnavailableFallback: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "trophy")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
