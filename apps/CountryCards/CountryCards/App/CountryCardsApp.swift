import SwiftUI

@main
struct CountryCardsApp: App {
    init() {
        // UIテストから「-uiTestReset」を付けて起動された時だけ、セーブデータを
        // まっさらにした上で無料ガチャを潤沢に用意する。1日の回数制限
        // (DailyBonusManager)を実装したことで、同じシミュレーター内で
        // テストを何度も回すとログインボーナス済みで無料ガチャが枯渇し、
        // テストが不安定になるのを防ぐための踏み台。本番の起動経路には一切影響しない。
        if ProcessInfo.processInfo.arguments.contains("-uiTestReset") {
            UITestSupport.resetAllStateForTesting()
        }
    }

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
