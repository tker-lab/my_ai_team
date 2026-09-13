import SwiftUI

/// 対戦画面。
///
/// 【2026-09-13仕様変更】デッキ編成の廃止に伴い、プレイヤーがカードを選ぶ操作は
/// 無くなった。両者のカードは自動で(持っているカードの中からランダムに)決まり、
/// 「対戦する」をタップすると火花演出とともに数値が公開され、勝敗が決まる。
/// 数値は決着が付くまで両者とも伏せておく(先に見えると当てっこにならないため)。
struct BattlePlayView: View {
    @StateObject private var viewModel: BattleViewModel
    @ObservedObject private var database = CardDatabase.shared

    init() {
        _viewModel = StateObject(wrappedValue: BattleViewModel(database: .shared, owned: .shared))
    }

    var body: some View {
        VStack {
            Text("あなた \(viewModel.playerWinCount)勝 - \(viewModel.cpuWinCount)勝 CPU")
                .font(.subheadline)
                .padding(.top)

            switch viewModel.phase {
            case .ready(let element, let highWins, let playerCard, let cpuCard):
                readyView(element: element, highWins: highWins, playerCard: playerCard, cpuCard: cpuCard)
            case .revealing(let round):
                revealingView(round: round)
            case .finished:
                finishedView
            }
        }
        .navigationTitle("対戦 \(min(viewModel.currentRoundNumber, BattleViewModel.totalRounds))/\(BattleViewModel.totalRounds)ターン目")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// カードは決まっているが、数値はまだ伏せてある状態。「対戦する」を
    /// タップすると決着が付く(=revealBattle()を呼ぶ)。
    private func readyView(element: CardElement, highWins: Bool, playerCard: Card, cpuCard: Card) -> some View {
        VStack(spacing: 16) {
            Text("お題:「\(element.displayName)」")
                .font(.title2.bold())
            Text(highWins ? "数値が高い方が勝ち!" : "数値が低い方が勝ち!")
                .font(.headline)
                .foregroundStyle(highWins ? .blue : .orange)

            Text("あなたとCPUのカードが決まりました。数値は対戦するまで分かりません。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            HStack(spacing: 24) {
                battleCardColumn(title: "あなた", card: playerCard, hideValue: true)
                Text("VS")
                    .font(.title.bold())
                    .foregroundStyle(.secondary)
                battleCardColumn(title: "CPU", card: cpuCard, hideValue: true)
            }
            .padding()

            Button("対戦する") { viewModel.revealBattle() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("battleFightButton")

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
                    battleCardColumn(title: "あなた", card: result.playerCard, hideValue: false, won: result.playerWon)
                    Text("⚡️")
                        .font(.system(size: 50))
                    battleCardColumn(title: "CPU", card: result.cpuCard, hideValue: false, won: !result.playerWon)
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
    /// `hideValue`がtrueの間は数値を「？？？」に伏せる(決着前の当てっこ演出)。
    /// 「なぜ勝った/負けたかが分かる」決定事項は、決着後(hideValue=false)に対応する。
    private func battleCardColumn(title: String, card: Card, hideValue: Bool, won: Bool = false) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            CardView(card: card, country: database.country(for: card.iso3), hideValue: hideValue)
                .scaleEffect(0.7)
            if !hideValue {
                Text(card.displayValue + card.element.unit)
                    .font(.footnote.bold())
                if won {
                    Text("WIN").font(.caption2.bold()).foregroundStyle(.green)
                }
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
