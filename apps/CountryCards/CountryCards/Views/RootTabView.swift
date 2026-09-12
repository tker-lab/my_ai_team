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

            ProfileView()
                .tabItem { Label("プロフィール", systemImage: "person.crop.circle") }
        }
    }
}

#Preview {
    RootTabView()
}
