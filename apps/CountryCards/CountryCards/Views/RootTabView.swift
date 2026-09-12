import SwiftUI

/// アプリ全体の入り口。「図鑑」「ガチャ」「対戦」「プロフィール」の4タブ構成。
struct RootTabView: View {
    @ObservedObject private var owned = OwnedCollection.shared

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
        // 決定事項どおり「ゲーム開始時に名前を決めて登録する」ため、ユーザー名が
        // 未登録の間は本編を覆う形で名前入力を必ず表示する
        // (チェック工程指摘:以前はプロフィール画面から後で任意に登録する形だった)。
        .fullScreenCover(isPresented: Binding(
            get: { owned.username == nil },
            set: { _ in }
        )) {
            OnboardingNameView()
        }
    }
}

#Preview {
    RootTabView()
}
