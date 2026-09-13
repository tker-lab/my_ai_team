import SwiftUI

/// ガチャを1回引く画面。「通常モード」「スキップモード」の操作フローを実装する。
/// 演出の作り込み(実際の動画・パーティクル等)はPhase 2に回し、ここでは
/// 状態遷移(タップ待ち→再生→カード表示、の分岐)が動くことを優先している。
struct GachaPlayView: View {
    let element: CardElement
    @StateObject private var viewModel: GachaPlayViewModel
    @ObservedObject private var database = CardDatabase.shared
    @ObservedObject private var dailyBonus = DailyBonusManager.shared

    init(element: CardElement) {
        self.element = element
        _viewModel = StateObject(wrappedValue: GachaPlayViewModel(
            element: element, database: .shared, owned: .shared, dailyBonus: .shared
        ))
    }

    var body: some View {
        VStack {
            if viewModel.pullResult == nil, viewModel.blockedByDailyLimit {
                noFreePullsView
            } else {
                switch viewModel.phase {
                case .introPaused, .introPlaying:
                    introView
                case .revealing(let index, let faceUp):
                    revealView(index: index, faceUp: faceUp)
                case .done:
                    resultSummaryView
                }
            }
        }
        .navigationTitle("\(element.displayName)ガチャ")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if viewModel.pullResult == nil {
                viewModel.startPull()
            }
        }
    }

    /// 無料ガチャの残り回数が0の時に出す画面。
    /// 【2026-09-13追加】CEOの実機確認フィードバック対応:「広告を見てもう1回引く」
    /// (本日の広告上限に達していなければ)と「¥100の10連を購入する」の2択を用意する。
    private var noFreePullsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "hourglass")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("本日の無料ガチャ回数を使い切りました")
                .font(.headline)
            Text("ログインボーナス・対戦の勝利でも無料ガチャが増えます。\nダブりポイントがあればそちらもすぐ引けます。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            exhaustedOptionsView
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 「広告を見てもう1回引く」「¥100の10連を購入する」の2択。無料ガチャを
    /// 使い切った直後(noFreePullsView)と、結果画面から「もう一度引く」を押して
    /// 使い切った時(resultSummaryView)の両方から共通で使う。
    private var exhaustedOptionsView: some View {
        VStack(spacing: 12) {
            if dailyBonus.adBonusRemainingToday > 0 {
                // 広告SDKは未組み込みのため、視聴完了をその場でシミュレートする
                // (実際の広告表示はPhase 2で組み込む。GachaHomeViewの
                // 「広告を見て+1回」ボタンと同じ仕組みを、この画面からも使えるようにする)。
                Button {
                    viewModel.watchAdForBonusPullThenRetry()
                } label: {
                    Text("広告を見てもう1回引く(本日あと\(dailyBonus.adBonusRemainingToday)回)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            NavigationLink {
                IAPGachaView(element: element)
            } label: {
                Text("¥100の10連を購入する")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - 導入演出(通常モード:タップ待ち / 再生中)

    private var introView: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 24) {
                Spacer()
                introArtwork
                Text(viewModel.phase == .introPaused ? "タップして開封" : "開封中...")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(introBackgroundColor)
            .contentShape(Rectangle())
            .onTapGesture { viewModel.tapIntro() }
            // VStackはそのままだと中の要素がバラバラのアクセシビリティ要素として
            // 扱われ、外側に付けたidentifierがUIテストから見えなくなる。
            // .combineで「1つのタップ領域」としてまとめてからidentifierを付ける。
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("gachaIntroArea")

            // 画面端の「スキップ」ボタン(決定事項:映像が始まった時点で出ている)。
            Button("スキップ") { viewModel.tapSkip() }
                .buttonStyle(.bordered)
                .tint(.white)
                .padding()
                .accessibilityIdentifier("gachaSkipButton")
        }
    }

    /// その回で一番高いレア度によって導入演出を4パターンに出し分ける
    /// (決定事項:N/SRのみ・SSR・UR・HURの4種)。Phase 1では色と簡単な
    /// アイコンだけで差を付ける簡易版。
    private var introBackgroundColor: Color {
        switch viewModel.pullResult?.highestRarity ?? .n {
        case .n, .sr: return Color(red: 0.25, green: 0.28, blue: 0.35)
        case .ssr: return Color(red: 0.15, green: 0.25, blue: 0.55)
        case .ur: return Color(red: 0.35, green: 0.15, blue: 0.55)
        case .hur: return Color(red: 0.55, green: 0.42, blue: 0.05)
        }
    }

    private var introArtwork: some View {
        Image(systemName: "shippingbox.fill")
            .font(.system(size: 80))
            .foregroundStyle(.white)
            .rotationEffect(.degrees(viewModel.phase == .introPlaying ? 15 : 0))
            .scaleEffect(viewModel.phase == .introPlaying ? 1.15 : 1.0)
            .animation(.easeInOut(duration: 0.6).repeatCount(2, autoreverses: true), value: viewModel.phase)
    }

    // MARK: - カード表示

    private func revealView(index: Int, faceUp: Bool) -> some View {
        VStack(spacing: 24) {
            Text("\(index + 1) / \(viewModel.pullResult?.cards.count ?? 3)枚目")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Group {
                if faceUp, let card = viewModel.pullResult?.cards[index] {
                    CardView(card: card, country: database.country(for: card.iso3))
                        .scaleEffect(1.2)
                        .transition(.opacity)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: 160, height: 220)
                        .overlay(Image(systemName: "questionmark").font(.largeTitle).foregroundStyle(.white))
                }
            }
            .id(index) // カードが変わるたびに見た目を作り直す(前のカードの状態が残らないように)

            Text(faceUp ? "タップして次へ" : "タップしてめくる")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.tapCard() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("gachaRevealArea")
    }

    // MARK: - 結果まとめ

    private var resultSummaryView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("結果")
                    .font(.title2.bold())
                    .padding(.top)

                ForEach(Array((viewModel.pullResult?.cards ?? []).enumerated()), id: \.offset) { offset, card in
                    let country = database.country(for: card.iso3)
                    VStack(spacing: 8) {
                        CardView(card: card, country: country)
                        if viewModel.isNewByIndex.indices.contains(offset), viewModel.isNewByIndex[offset] {
                            Text("New!")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                        }
                        CardShareButton(card: card, country: country)
                    }
                }

                if viewModel.blockedByDailyLimit {
                    Text("本日の無料ガチャ回数を使い切りました")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top)
                    exhaustedOptionsView
                        .padding(.horizontal, 32)
                } else {
                    Button("もう一度引く") { viewModel.startPull() }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                }
                Spacer().frame(height: 32)
            }
            .padding()
        }
    }
}
