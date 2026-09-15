import SwiftUI

struct GachaOddsView: View {
    enum Source { case general, iapTenPull, point }
    var source: Source = .general
    var body: some View { ZStack { EarthBackdrop(variant: .gacha(.ur)); ScrollView { VStack(spacing: 14) {
        EarthTopBar(title: "排出確率") { Image(systemName: "percent").foregroundStyle(EarthColors.gold) }
        oddsPanel("1・2枚目", [("N","70%"),("SR","22%"),("SSR","6%"),("UR","2%")])
        oddsPanel("3枚目（SR以上確定）", [("SR","82%"),("SSR","15%"),("UR","3%")])
        guarantees
        ArchivePanel(variant: .warning) { VStack(alignment: .leading, spacing: 8) { Text("HUR・北朝鮮のGDP").font(.headline); Text("1 / 20,000,000").font(.title2.bold()).foregroundStyle(EarthColors.gold); Text("すべての抽選より前に判定されます。").font(.caption).foregroundStyle(EarthColors.secondary) } }
        ArchivePanel { Text("ダブりポイントガチャもレア度確率は同一です。未所持優先はレア度決定後の国抽選にのみ作用します。").font(.caption).foregroundStyle(EarthColors.secondary) }
    }.padding(.horizontal) } }.earthNavigationTitle("排出確率") }

    private func oddsPanel(_ title: String, _ rows: [(String,String)]) -> some View { ArchivePanel { VStack(spacing: 10) { Text(title).font(.headline).frame(maxWidth: .infinity, alignment: .leading); ForEach(Array(rows.enumerated()), id: \.offset) { _, row in HStack { RarityBadge(rarity: Rarity(rawValue: row.0) ?? .n); Spacer(); Text(row.1).fontWeight(.black).monospacedDigit() } } } } }
    @ViewBuilder private var guarantees: some View {
        switch source {
        case .general:
            guarantee("¥100・10連の30枚目", "SSR 75% / UR 25%")
            guarantee("ポイント10連の30枚目", "SR 82% / SSR 15% / UR 3%")
            guarantee("ポイント100連の300枚目", "SSR 75% / UR 25%")
        case .iapTenPull: guarantee("この10連の30枚目", "SSR 75% / UR 25%")
        case .point:
            guarantee("ポイント10連の30枚目", "SR 82% / SSR 15% / UR 3%")
            guarantee("ポイント100連の300枚目", "SSR 75% / UR 25%")
        }
    }
    private func guarantee(_ title: String, _ detail: String) -> some View { ArchivePanel(variant: .raised) { VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(detail).foregroundStyle(EarthColors.cyan).fontWeight(.bold) } } }
}
