import SwiftUI

struct RootTabView: View {
    @ObservedObject private var owned = OwnedCollection.shared
    @State private var selection: ExpeditionTab = .home
    @State private var navigationReset = 0
    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Group { switch selection { case .home: HomeDashboardView(openGacha: { selection = .gacha }, openCollection: { selection = .collection }, openBattle: { selection = .battle }, openProfile: { selection = .profile }); case .collection: CollectionHomeView(); case .gacha: GachaHomeView(); case .battle: BattleHomeView(); case .profile: ProfileView() } }.id("\(selection.rawValue)-\(navigationReset)").frame(width: proxy.size.width).frame(maxHeight: .infinity).clipped()
                AdDock().frame(width: proxy.size.width).fixedSize(horizontal: false, vertical: true).layoutPriority(2)
                ExpeditionTabBar(selection: $selection, onReselect: { _ in navigationReset += 1 }).frame(width: proxy.size.width).fixedSize(horizontal: false, vertical: true).layoutPriority(2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }.background(EarthColors.abyss).preferredColorScheme(.dark)
        .onAppear { StartingCardsProvisioner.grantStartingCardsIfNeeded(database: .shared, owned: .shared) }
        .fullScreenCover(isPresented: Binding(get: { owned.username == nil }, set: { _ in })) { OnboardingNameView() }
    }
}

#Preview { RootTabView() }
