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
        ZStack { EarthBackdrop(variant: .battle); VStack {
            EarthTopBar(title: "対戦 \(min(viewModel.currentRoundNumber, BattleViewModel.totalRounds))/\(BattleViewModel.totalRounds)") { EmptyView() }
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
        } }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// お題とCPUのカードは決まっているが、プレイヤーはまだ4枚から1枚を選んでいない状態。
    /// CPUのカードを画面奥(上側)、プレイヤーの手札4枚を画面手前(下側)に配置する。
    private func choosingView(element: CardElement, highWins: Bool, cpuCard: Card, candidates: [Card]) -> some View {
        // 画面の縦幅が狭い端末でも、できるだけスクロールせずに「CPUの1枚+自分の4枚」を
        // 一望できるよう、カードの拡大率と余白を詰めてある(スクロール自体はできるので
        // 収まりきらなくても操作不能にはならない)。
        ScrollView {
            VStack(spacing: 14) {
                Text("お題:「\(element.displayName)」")
                    .font(.title2.bold())
                // 【2026-09-14調整】「このターンは高い/低いどちらが勝ちか」はプレイヤーが
                // カードを選ぶ判断に直結する最重要情報のため、文字を大きくし色付きの
                // カプセル背景を付けて目立たせる(以前はheadlineの色文字のみで目立たない
                // との指摘があった)。
                Text(highWins ? "数値が高い方が勝ち!" : "数値が低い方が勝ち!")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(highWins ? EarthColors.blue : EarthColors.amber, in: RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 4) {
                    Text("CPUの手札(数値は選ぶまで分かりません)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    CollectibleCardView(card: cpuCard, country: database.country(for: cpuCard.iso3), size: .battle, revealState: .valueHidden, hidesRarity: true)
                }

                Rectangle().fill(EarthColors.line).frame(height: 1).padding(.horizontal, 32)

                VStack(spacing: 8) {
                    Text("あなたの手札から1枚選んでください")
                        .font(.subheadline.bold())

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(candidates) { card in
                            Button {
                                viewModel.choosePlayerCard(card)
                            } label: {
                                CollectibleCardView(card: card, country: database.country(for: card.iso3), size: .mini, revealState: .valueHidden, hidesRarity: true)
                            }
                            .accessibilityIdentifier("battleCandidateButton")
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer(minLength: 12)
            }
            .padding(.top, 4)
        }
    }

    private func revealingView(round: Int) -> some View {
        guard let result = viewModel.roundResults.last else { return AnyView(EmptyView()) }
        // 決着後に見せる「選ばなかった3枚」(候補4枚から選んだ1枚を除いたもの)。
        // 【2026-09-14仕様追加】その場に提示されていた4枚全部の数値を公開する。
        let otherCandidates = result.candidates.filter { $0.id != result.playerCard.id }

        let resultText: String
        let resultColor: Color
        switch result.outcome {
        case .playerWin:
            resultText = "このターンはあなたの勝ち!"
            resultColor = .green
        case .cpuWin:
            resultText = "このターンはCPUの勝ち"
            resultColor = .red
        case .draw:
            // 【2026-09-14バグ修正】数値が同じ時は「引き分け」として表示する
            // (以前はここが必ず「CPUの勝ち」になっていた)。
            resultText = "このターンは引き分け"
            resultColor = .gray
        }

        return AnyView(
            ScrollView {
                VStack(spacing: 16) {
                    Text("お題:「\(result.element.displayName)」(\(result.highWins ? "高い方が勝ち" : "低い方が勝ち"))")
                        .font(.subheadline)

                    HStack(spacing: 24) {
                        battleCardColumn(title: "あなた", card: result.playerCard, badge: result.outcome == .playerWin ? "WIN" : (result.outcome == .draw ? "DRAW" : nil))
                        Image(systemName: "bolt.fill").font(.system(size: 38)).foregroundStyle(EarthColors.gold)
                        battleCardColumn(title: "CPU", card: result.cpuCard, badge: result.outcome == .cpuWin ? "WIN" : (result.outcome == .draw ? "DRAW" : nil))
                    }
                    .padding()

                    Text(resultText)
                        .font(.title3.bold())
                        .foregroundStyle(resultColor)

                    if !otherCandidates.isEmpty {
                        Rectangle().fill(EarthColors.line).frame(height: 1).padding(.horizontal, 32)
                        VStack(spacing: 6) {
                            Text("選ばなかった手札")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                ForEach(otherCandidates) { card in
                                    CollectibleCardView(card: card, country: database.country(for: card.iso3), size: .mini, hidesRarity: true)
                                }
                            }
                        }
                    }

                    Button("次へ") { viewModel.proceedAfterReveal() }
                        .buttonStyle(EarthActionButtonStyle())
                        .padding(.top)
                    Spacer(minLength: 12)
                }
                .padding(.top)
            }
        )
    }

    /// カードと、そのカードの実際の数値(単位付き)を並べて見せる。決着後(hideValue=false)
    /// のカードにのみ呼ぶ想定。「なぜ勝った/負けたかが分かる」決定事項に対応する。
    private func battleCardColumn(title: String, card: Card, badge: String? = nil) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            CollectibleCardView(card: card, country: database.country(for: card.iso3), size: .battle, hidesRarity: true)
            Text(card.displayValue + card.element.unit)
                .font(.footnote.bold())
            if let badge {
                Text(badge)
                    .font(.caption2.bold())
                    .foregroundStyle(badge == "DRAW" ? .gray : .green)
            }
        }
    }

    private var finishedView: some View {
        // 【2026-09-14仕様】5ターン終えた結果、勝ち数が同じ(試合トータルが引き分け)に
        // なるのも問題ない仕様として扱う。無理に決着を付けない。
        let matchText: String
        let matchColor: Color
        if viewModel.playerWinCount > viewModel.cpuWinCount {
            matchText = "対戦に勝利しました!"
            matchColor = .green
        } else if viewModel.playerWinCount < viewModel.cpuWinCount {
            matchText = "対戦に敗北しました"
            matchColor = .red
        } else {
            matchText = "対戦は引き分けでした"
            matchColor = .gray
        }
        let record = "\(viewModel.playerWinCount)勝\(viewModel.cpuWinCount)敗"
            + (viewModel.drawCount > 0 ? "\(viewModel.drawCount)分" : "")

        return VStack(spacing: 16) {
            Text(matchText)
                .font(.title.bold())
                .foregroundStyle(matchColor)
            Text(record)
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
