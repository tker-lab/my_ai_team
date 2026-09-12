import SwiftUI

/// カードのレア度(珍しさ)。数が少ないものほど珍しい。
///
/// なぜenum(列挙型)にしたか: レア度は「N/SR/SSR/UR/HUR」の5種類しか
/// 存在しない、という制約をSwiftの型として表現するため。文字列(String)で
/// 持つこともできるが、そうすると誤字(例:"Ssr")が入り込む余地が生まれる。
/// enumならコンパイラがタイプミスを検出してくれる。
enum Rarity: String, Codable, CaseIterable, Comparable {
    case n = "N"
    case sr = "SR"
    case ssr = "SSR"
    case ur = "UR"
    /// 北朝鮮のGDPカード専用の最上位レア度(1枚のみ)。HUR = "Hyper Ultra Rare"のような
    /// 位置づけの造語(app_team_country_cards.mdの決定どおり)。
    case hur = "HUR"

    /// 排出されにくい順(弱い→強い)の並び順。Comparableに準拠させることで
    /// `rarity1 < rarity2` のような比較や、ソートがそのまま書けるようになる。
    private var sortOrder: Int {
        switch self {
        case .n: return 0
        case .sr: return 1
        case .ssr: return 2
        case .ur: return 3
        case .hur: return 4
        }
    }

    static func < (lhs: Rarity, rhs: Rarity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    /// 画面に出す日本語ラベル(基本はコードそのものでよいが、将来変更しやすいよう一箇所にまとめる)
    var displayName: String { rawValue }

    /// カード全体のベース色(レア度で決める、というapp_team_country_cards.mdの配色ルール)。
    /// 業界標準の「白/灰→緑→青→紫→金」に寄せた暫定色。実際の色味の微調整は
    /// 実機で見ながら行う想定(Phase 2で配色の作り込みをする際に差し替えてよい)。
    var baseColor: Color {
        switch self {
        case .n: return Color(white: 0.85)
        case .sr: return Color(red: 0.25, green: 0.65, blue: 0.35)
        case .ssr: return Color(red: 0.20, green: 0.45, blue: 0.85)
        case .ur: return Color(red: 0.55, green: 0.30, blue: 0.80)
        case .hur: return Color(red: 0.85, green: 0.70, blue: 0.15) // 別格の金色
        }
    }

    /// SSR以上はうっすら、URはしっかりキラキラ演出を付ける(決定事項どおり)。
    /// この段階(Phase 1)では「キラキラの強さの目安」だけを持たせておき、
    /// 実際のエフェクト描画はPhase 2で作り込む。
    var sparkleIntensity: Double {
        switch self {
        case .n, .sr: return 0
        case .ssr: return 0.3
        case .ur: return 0.7
        case .hur: return 1.0
        }
    }
}
