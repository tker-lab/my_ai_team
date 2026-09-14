import SwiftUI

/// 対戦画面。
///
/// 【2026-09-14仕様変更】「自動でランダムに1枚出す」方式をやめ、選択式に変更した。
/// お題が決まると、まずCPU側のカードを1枚(国・要素は見える、数値は「？？？」)
/// 画面奥(上側)に提示する。続けて、プレイヤーの手札(その要素で持っているカードの
/// 中から4枚、数値は伏せたまま)を画面手前(下側)に並べ、タップして1枚選ばせる。
/// 選ぶと両者の数値がまとめて公開され、決着が付く。
/// 狙いは「ランダムに1枚出るだけ」の運ゲー感を無くし、相手の顔ぶれを見てから
/// 自分のどのカードを出すか選ぶ駆け引きを持たせること。
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
            case .choosing(let element, let highWins, let cpuCard, let candidates):
                choosingView(element: element, highWins: highWins, cpuCard: cpuCard, candidates: candidates)
            case .revealing(let round):
                revealingView(round: round)
            case .finished:
                finishedView
            }
        }
        .navigationTitle("対戦 \(min(viewModel.currentRoundNumber, BattleViewModel.totalRounds))/\(BattleViewModel.totalRounds)ターン目")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// お題とCPUのカードは決まっているが、プレイヤーはまだ4枚から1枚を選んでいない状態。
    /// CPUのカードを画面奥(上側)、プレイヤーの手札4枚を画面手前(下側)に配置する。
    private func choosingView(element: CardElement, highWins: Bool, cpuCard: Card, candidates: [Card]) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("お題:「\(element.displayName)」")
                    .font(.title2.bold())
                Text(highWins ? "数値が高い方が勝ち!" : "数値が低い方が勝ち!")
                    .font(.headline)
                    .foregroundStyle(highWins ? .blue : .orange)

                VStack(spacing: 6) {
                    Text("CPUの手札(数値は選ぶまで分かりません)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    CardView(card: cpuCard, country: database.country(for: cpuCard.iso3), hideValue: true)
                        .scaleEffect(0.8)
                }
                .padding(.vertical, 8)

                Divider()
                    .padding(.horizontal, 32)

                VStack(spacing: 10) {
                    Text("あなたの手札から1枚選んでください")
                        .font(.subheadline.bold())

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(candidates) { card in
                            Button {
                                viewModel.choosePlayerCard(card)
                            } label: {
                                CardView(card: card, country: database.country(for: card.iso3), hideValue: true)
                                    .scaleEffect(0.62)
                                    .frame(width: 160 * 0.62, height: 220 * 0.62)
                            }
                            .accessibilityIdentifier("battleCandidateButton")
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer(minLength: 24)
            }
            .padding(.top, 8)
        }
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
                    .buttonStyle(.gamePrimary)
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
