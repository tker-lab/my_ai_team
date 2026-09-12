import SwiftUI

@main
struct CountryCardsApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .onAppear {
                    // Game Centerへのサインイン状態を起動時に確認しておく
                    // (未サインインならシステムがサインイン画面を出してくれる)。
                    GameCenterManager.shared.authenticate()
                }
        }
    }
}
