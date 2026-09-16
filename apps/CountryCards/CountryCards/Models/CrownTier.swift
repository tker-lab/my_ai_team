import SwiftUI

/// プロフィール画面に出す「実績の王冠」。持っているカードの種類数(ダブり除く)
/// に応じて10段階で色が変わる(決定事項)。
///
/// 正式データは全1,923枚で、「1,922枚で銀・1,923枚で金」という区切り。
/// 将来のデータ更新で収録数が変わっても最後の1枚と完全制覇を正しく判定するため、
/// 末尾2段階だけは実際に収録されたカード総数から動的に計算する。
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
