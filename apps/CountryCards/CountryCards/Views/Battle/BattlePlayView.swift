import SwiftUI

/// 対戦画面。「どの要素・どちらが勝ちか」を毎ターン表示し、プレイヤーは
/// デッキからカードを1枚選ぶ→火花演出とともに両者の実際の数値を見せて
/// 勝敗を伝える、を5ターン繰り返す。
struct BattlePlayView: View {
    @StateObject private var viewModel: BattleViewModel
    @ObservedObject private var database = CardDatabase.shared

    init() {
        _viewModel = StateObject(wrappedValue: BattleViewModel(
            database: .shared, deckManager: .shared, owned: .shared
        ))
    }

    var body: some View {
        VStack {
            Text("あなた \(viewModel.playerWinCount)勝 - \(viewModel.cpuWinCount)勝 CPU")
                .font(.subheadline)
                .padding(.top)

            switch viewModel.phase {
            case .choosingCard(let element, let highWins):
                choosingView(element: element, highWins: highWins)
            case .revealing(let round):
                revealingView(round: round)
            case .finished:
                finishedView
            }
        }
        .navigationTitle("対戦 \(min(viewModel.currentRoundNumber, BattleViewModel.totalRounds))/\(BattleViewModel.totalRounds)ターン目")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choosingView(element: CardElement, highWins: Bool) -> some View {
        VStack(spacing: 16) {
            Text("お題:「\(element.displayName)」")
                .font(.title2.bold())
            Text(highWins ? "数値が高い方が勝ち!" : "数値が低い方が勝ち!")
                .font(.headline)
                .foregroundStyle(highWins ? .blue : .orange)

            Text("あなたの手札から1枚選んでください")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(viewModel.deckCards(for: element)) { card in
                        Button {
                            viewModel.choose(card)
                        } label: {
                            CardView(card: card, country: database.country(for: card.iso3))
                                .scaleEffect(0.75)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            Spacer()
        }
        .padding(.top)
    }

    private func revealingView(round: Int) -> some View {
        guard let result = viewModel.roundResults.last else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(spacing: 16) {
                Text("お題:「\(result.element.displayName)」(\(result.highWins ? "高い方が勝ち" : "低い方が勝ち"))")
                    .font(.subheadline)

                HStack(spacing: 24) {
                    battleCardColumn(title: "あなた", card: result.playerCard, won: result.playerWon)
                    Text("⚡️")
                        .font(.system(size: 50))
                    battleCardColumn(title: "CPU", card: result.cpuCard, won: !result.playerWon)
                }
                .padding()

                Text(result.playerWon ? "このターンはあなたの勝ち!" : "このターンはCPUの勝ち")
                    .font(.title3.bold())
                    .foregroundStyle(result.playerWon ? .green : .red)

                Button("次へ") { viewModel.proceedAfterReveal() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                Spacer()
            }
            .padding(.top)
        )
    }

    /// カードと、そのカードの実際の数値(単位付き)を並べて見せる。
    /// 「なぜ勝った/負けたかが分かる」ようにする決定事項に対応。
    private func battleCardColumn(title: String, card: Card, won: Bool) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            CardView(card: card, country: database.country(for: card.iso3))
                .scaleEffect(0.7)
            Text(card.displayValue + card.element.unit)
                .font(.footnote.bold())
            if won {
                Text("WIN").font(.caption2.bold()).foregroundStyle(.green)
            }
        }
    }

    private var finishedView: some View {
        VStack(spacing: 16) {
            Text(viewModel.playerWinCount > viewModel.cpuWinCount ? "対戦に勝利しました!" : "対戦に敗北しました")
                .font(.title.bold())
                .foregroundStyle(viewModel.playerWinCount > viewModel.cpuWinCount ? .green : .red)
            Text("\(viewModel.playerWinCount)勝 \(viewModel.cpuWinCount)敗")
                .font(.headline)
            if viewModel.playerWinCount > viewModel.cpuWinCount {
                Text(viewModel.wonFreeGachaBonus
                    ? "報酬: 無料ガチャ +1回"
                    : "本日の対戦報酬(1日3回)はすでに受け取り済みです")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 40)
    }
}
