import SwiftUI

/// アプリ全体の入り口。「図鑑」「ガチャ」の2タブ構成(Phase 1のスコープ)。
/// バトル・デッキ編成タブはPhase 2で追加する。
struct RootTabView: View {
    var body: some View {
        TabView {
            CollectionHomeView()
                .tabItem { Label("図鑑", systemImage: "book.closed") }

            GachaHomeView()
                .tabItem { Label("ガチャ", systemImage: "shippingbox") }

            BattleHomeView()
                .tabItem { Label("対戦", systemImage: "bolt.fill") }

            ProfileView()
                .tabItem { Label("プロフィール", systemImage: "person.crop.circle") }
        }
        .onAppear {
            // 初回起動時だけ、要素ごとにNレアのカードを5枚ずつ持った状態から
            // スタートする(決定事項どおりの初期デッキ)。
            DeckManager.shared.seedInitialDeckIfNeeded(database: .shared, owned: .shared)
        }
    }
}

#Preview {
    RootTabView()
}
