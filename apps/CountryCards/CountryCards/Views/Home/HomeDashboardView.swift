import SwiftUI

enum ExpeditionTab: String, CaseIterable { case home = "ホーム", collection = "図鑑", gacha = "ガチャ", battle = "対戦", profile = "記録"
    var icon: String { switch self { case .home: "globe.asia.australia.fill"; case .collection: "rectangle.stack.fill"; case .gacha: "sparkles.square.filled.on.square"; case .battle: "bolt.shield.fill"; case .profile: "person.crop.circle.fill" } }
}

struct ExpeditionTabBar: View {
    @Binding var selection: ExpeditionTab
    var onReselect: (ExpeditionTab) -> Void = { _ in }
    var body: some View { GeometryReader { proxy in HStack(spacing: 0) {
        ForEach(ExpeditionTab.allCases, id: \.self) { tab in tabButton(tab, width: proxy.size.width / CGFloat(ExpeditionTab.allCases.count) - 2) }
    }.padding(.horizontal, 5) }.frame(height: 92).background(EarthColors.abyss.opacity(0.98)).overlay(alignment: .top) { Rectangle().fill(EarthColors.line).frame(height: 1) } }

    private func tabButton(_ tab: ExpeditionTab, width: CGFloat) -> some View {
        let selected = selection == tab
        return Button { selected ? onReselect(tab) : (selection = tab) } label: {
            ZStack {
                Color.clear
                VStack(spacing: 4) {
                    Image(systemName: tab.icon).font(.system(size: tab == .gacha ? 23 : 19, weight: .bold))
                    Text(tab.rawValue).font(.system(size: 10, weight: .bold))
                    Rectangle().fill(selected ? EarthColors.cyan : .clear).frame(width: 24, height: 2)
                }
                .foregroundStyle(selected ? EarthColors.cyan : EarthColors.secondary)
                .frame(width: tab == .gacha ? 72 : width - 2, height: tab == .gacha ? 72 : 55)
                .background(selected ? EarthColors.cyan.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .offset(y: tab == .gacha ? -8 : 0)
            }.frame(width: width, height: 84).contentShape(Rectangle())
        }.accessibilityIdentifier("tab_\(tab.rawValue)").accessibilityValue(selected ? "選択中" : "未選択")
    }
}

struct HomeDashboardView: View {
    @ObservedObject private var owned = OwnedCollection.shared
    @ObservedObject private var database = CardDatabase.shared
    @ObservedObject private var bonus = DailyBonusManager.shared
    let openGacha: () -> Void; let openCollection: () -> Void; let openBattle: () -> Void; let openProfile: () -> Void
    var body: some View { NavigationStack { ZStack {
        EarthBackdrop(variant: .home)
        ScrollView { VStack(spacing: 16) {
            EarthTopBar(title: "EARTH ARCHIVE") { ResourceChip(label: "DUP", value: "\(owned.dupePoints)", tint: EarthColors.gold) }
            HStack { Image(systemName: "crown.fill").foregroundStyle(EarthColors.gold); Text(owned.username ?? "EXPLORER").font(.headline); Spacer(); Button("全国ランキング", action: openProfile).font(.caption.bold()).foregroundStyle(EarthColors.cyan) }
            ArchivePanel(variant: .hero) { HStack(spacing: 20) {
                CollectionProgressOrb(owned: owned.uniqueCardCount, total: max(database.cards.count, 1)).frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 7) { Text("世界記録の収集率").font(.headline); Text("次の未知を記録しよう").foregroundStyle(EarthColors.secondary); Button("図鑑を開く", action: openCollection).foregroundStyle(EarthColors.cyan).fontWeight(.bold) }
            } }
            Button(action: openGacha) { Label(bonus.freePullsAvailable > 0 ? "今日の探索を始める  残り\(bonus.freePullsAvailable)回" : "無料分終了・広告/ポイントで探索", systemImage: "sparkles") }.buttonStyle(EarthActionButtonStyle())
            HStack(spacing: 12) { Button(action: openBattle) { Label("対戦遠征", systemImage: "bolt.shield.fill") }.buttonStyle(EarthActionButtonStyle(variant: .secondary)); Button(action: openCollection) { Label("図鑑", systemImage: "rectangle.stack.fill") }.buttonStyle(EarthActionButtonStyle(variant: .secondary)) }
            HStack(spacing: 8) { todayState("広告", "残\(bonus.adBonusRemainingToday)"); todayState("対戦報酬", "残\(bonus.battleBonusRemainingToday)"); todayState("ログイン", "受取済み") }
        }.padding(.horizontal, 16).padding(.bottom, 18) }
    }.toolbar(.hidden, for: .navigationBar) } }

    private func todayState(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) { Text(title).font(.caption2).foregroundStyle(EarthColors.secondary); Text(value).font(.caption.bold()).foregroundStyle(EarthColors.text) }
            .frame(maxWidth: .infinity, minHeight: 44).background(EarthColors.panel, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(EarthColors.line))
    }
}
