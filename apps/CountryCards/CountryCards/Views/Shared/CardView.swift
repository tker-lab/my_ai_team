import SwiftUI

/// カード1枚の見た目(コレクション画面・ガチャ演出の両方から共通で使う)。
///
/// 配色ルール(app_team_country_cards.md決定事項):
///   - カード全体のベース色 = レア度(Rarity.baseColor)
///   - 縁(枠線)の色 = 要素(CardElement.borderColor)
/// Phase 1では「キラキラエフェクト」などの作り込みは行わず、色分けと
/// 情報表示ができていることを優先する(演出の作り込みはPhase 2)。
struct CardView: View {
    let card: Card
    let country: Country?
    /// false の場合はシルエット表示(図鑑で未入手カードを見せる時に使う)。
    var isRevealed: Bool = true

    var body: some View {
        VStack(spacing: 8) {
            flagArea
            Text(country?.nameJa ?? "???")
                .font(.headline)
                .lineLimit(1)
            Text(card.element.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if isRevealed {
                Text(card.displayValue + card.element.unit)
                    .font(.title3.bold())
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
