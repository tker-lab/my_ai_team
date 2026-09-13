import SwiftUI

/// カード1枚の見た目(コレクション画面・ガチャ演出の両方から共通で使う)。
///
/// 配色ルール(app_team_country_cards.md決定事項):
///   - カード全体のベース色 = レア度(Rarity.baseColor)
///   - 縁(枠線)の色 = 要素(CardElement.borderColor)
///   - SSR以上はうっすら、URはしっかりキラキラのエフェクトを付ける
///     (SparkleOverlayで実装。sparkleIntensityの値でキラキラの強さを変える)
struct CardView: View {
    let card: Card
    let country: Country?
    /// false の場合はシルエット表示(図鑑で未入手カードを見せる時に使う)。
    var isRevealed: Bool = true
    /// true の場合、国旗・国名・レア度はそのまま見せつつ数値だけ「？？？」に伏せる。
    /// 【2026-09-13追加】対戦中、決着がつくまで両者の数値を隠すために使う
    /// (isRevealedとは別軸:isRevealed=falseはカード自体が未入手で全て伏せる、
    /// hideValue=trueはカードの中身は分かるが数値だけ勝負の決着まで伏せる)。
    var hideValue: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            flagArea
            // 【2026-09-13修正】サントメ・プリンシペ等、長い国名がカードからはみ出す
            // バグへの対応。lineLimit(1)だけでは幅に収まらない文字が見切れて
            // しまうため、minimumScaleFactorで自動的に文字を縮めて収める。
            Text(country?.nameJa ?? "???")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
            Text(card.element.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if isRevealed, hideValue {
                Text("？？？")
                    .font(.title3.bold())
            } else if isRevealed {
                // 【2026-09-13修正】数値の文字がカードの縁と重なるバグへの対応。
                // 桁の多い数値でもカード幅(160pt)に収まるよう、自動縮小+1行固定にする。
                Text(card.displayValue + card.element.unit)
                    .font(.title3.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 6)
                if let year = card.year {
                    Text("\(year)年のデータ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("？？？")
                    .font(.title3.bold())
            }
            RarityBadge(rarity: card.rarity)
        }
        .padding(12)
        .frame(width: 160, height: 220)
        .background(isRevealed ? card.rarity.baseColor : Color(white: 0.75))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isRevealed ? card.element.borderColor : .gray, lineWidth: 4)
        )
        .shadow(radius: card.rarity.sparkleIntensity > 0 ? 6 : 2)
        .overlay {
            if isRevealed, card.rarity.sparkleIntensity > 0 {
                SparkleOverlay(intensity: card.rarity.sparkleIntensity)
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    @ViewBuilder
    private var flagArea: some View {
        if isRevealed, let url = country?.flagImageURL() {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    // 通信できない・画像取得失敗時も国名だけで成立するようにする
                    // (オフラインでもカードの中身は読めるべき、という設計方針)。
                    Color.gray.opacity(0.3)
                }
            }
            .frame(height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.4))
                .frame(height: 70)
                .overlay(Image(systemName: "questionmark").font(.largeTitle))
        }
    }
}

/// SSR以上のカードに乗せる簡易キラキラ演出。GeometryReaderは使わず、固定位置
/// に配置した「✨」を明滅させるだけの軽い実装(見た目の作り込みはPhase 2で
/// 続けられるよう、まずは「レア度が高いほど華やかに見える」を成立させる)。
private struct SparkleOverlay: View {
    let intensity: Double // 0(無し)〜1(URクラス)
    @State private var isAnimating = false

    private var sparklePositions: [(x: CGFloat, y: CGFloat, delay: Double)] {
        [(0.15, 0.15, 0), (0.85, 0.25, 0.3), (0.75, 0.85, 0.6), (0.2, 0.8, 0.9)]
    }

    var body: some View {
        ZStack {
            ForEach(Array(sparklePositions.enumerated()), id: \.offset) { _, pos in
                Image(systemName: "sparkle")
                    .font(.system(size: 14 + 6 * intensity))
                    .foregroundStyle(.white.opacity(0.9))
                    .opacity(isAnimating ? 0.9 : 0.1)
                    .position(x: 160 * pos.x, y: 220 * pos.y) // CardViewの固定サイズ(160x220)に合わせる
                    .animation(
                        .easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(pos.delay),
                        value: isAnimating
                    )
            }
        }
        .frame(width: 160, height: 220)
        .onAppear { isAnimating = true }
    }
}

/// レア度を示す小さなバッジ(N/SR/SSR/UR/HUR)。
struct RarityBadge: View {
    let rarity: Rarity

    var body: some View {
        Text(rarity.displayName)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(rarity.baseColor)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(.black.opacity(0.2)))
    }
}
