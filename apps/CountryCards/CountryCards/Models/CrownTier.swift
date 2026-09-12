import SwiftUI

/// プロフィール画面に出す「実績の王冠」。持っているカードの種類数(ダブり除く)
/// に応じて10段階で色が変わる(決定事項)。
///
/// 【重要な注意】app_team_country_cards.mdは「全カード数1,923枚」を前提に
/// 「1,922枚で銀・1,923枚で金」という区切りを決めている。しかし実際に
/// generate_cards.pyで生成できたカードは1,885枚(2026-09-12時点)で、
/// 想定より少ない。差の主因は「隣接国の数」要素で、無料の代替データ源
/// (countries.dev。本家REST Countriesはアカウント登録のメール確認が必要で
/// 今夜は完了できなかった)が、シンガポール(マレーシアと陸続きの橋がある)や
/// チェコ(複数の陸上国境がある)のような一部の国で、本来あるはずの隣接国
/// 情報を欠落させていた。「データが無い国のカードは作らない」という
/// このアプリの大原則を優先し、不確かな値を推測で埋めるのではなくカード自体を
/// 作らない判断をしたため、実際の総数が1,923より少なくなっている。
/// 【暫定対応】そのため「最後の1枚まで=銀」「完全制覇=金」の2段階は
/// 1,923ではなく実際の総数を基準に動的計算する。途中の7段階
/// (100/200/300/500/700/1,000/1,500枚)は決定事項の数字をそのまま使う
/// (実際の総数1,885枚の範囲内に収まるため据え置きで問題ない)。
/// 次回データ更新時にREST Countries本家へ切り替えられれば1,923に近づく想定。
enum CrownTier: Int, CaseIterable, Comparable {
    case tier1 = 1
    case tier2, tier3, tier4, tier5, tier6, tier7, tier8, tier9, tier10

    static func < (lhs: CrownTier, rhs: CrownTier) -> Bool { lhs.rawValue < rhs.rawValue }

    /// 固定の区切り(決定事項の数字。総数に関わらずこのまま使う)。
    private static let fixedThresholds = [100, 200, 300, 500, 700, 1000, 1500]

    /// 持っているユニークカード数と、実際に存在するカード総数から段階を求める。
    static func current(uniqueOwnedCount: Int, totalCardCount: Int) -> CrownTier {
        if uniqueOwnedCount >= totalCardCount { return .tier10 } // 完全制覇(金)
        if uniqueOwnedCount >= totalCardCount - 1 { return .tier9 } // 残り1枚(銀)
        var tier = CrownTier.tier1
        for (index, threshold) in fixedThresholds.enumerated() {
            if uniqueOwnedCount >= threshold {
                tier = CrownTier(rawValue: index + 2) ?? tier
            }
        }
        return tier
    }

    /// 王冠の色。「後にいくほど良い色に見える」順で、最後は銀→金で固定
    /// (決定事項どおり)。途中の色の並びは部署の一任。
    var color: Color {
        switch self {
        case .tier1: return Color(white: 0.6)             // 灰
        case .tier2: return Color(red: 0.72, green: 0.53, blue: 0.35) // 銅
        case .tier3: return .green
        case .tier4: return .mint
        case .tier5: return .blue
        case .tier6: return .indigo
        case .tier7: return .purple
        case .tier8: return Color(red: 0.85, green: 0.2, blue: 0.35) // 紅
        case .tier9: return Color(white: 0.82) // 銀
        case .tier10: return Color(red: 0.85, green: 0.70, blue: 0.15) // 金
        }
    }
}
