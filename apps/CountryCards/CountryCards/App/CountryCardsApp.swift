import SwiftUI

@main
struct CountryCardsApp: App {
    init() {
        // UIテストから「-uiTestReset」を付けて起動された時だけ、セーブデータを
        // まっさらにした上で無料ガチャを潤沢に用意する。1日の回数制限
        // (DailyBonusManager)を実装したことで、同じシミュレーター内で
        // テストを何度も回すとログインボーナス済みで無料ガチャが枯渇し、
        // テストが不安定になるのを防ぐための踏み台。本番の起動経路には一切影響しない。
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTestReset") {
            UITestSupport.resetAllStateForTesting()
        } else if arguments.contains("-uiTestResetNoUsername") {
            // オンボーディング(名前入力)画面そのものをテストする時専用。
            UITestSupport.resetAllStateForTesting(presetUsername: false)
        } else if arguments.contains("-uiTestSeedNineCardCountry") {
            // カードが9種類しか存在しない国(モナコ)の9枚を所持済みにする。
            // 豆知識10個が固定分母10ではなく実カード枚数で解放されるかの確認専用。
            UITestSupport.seedNineCardCountryForTrivia()
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .onAppear {
                    // Game Centerへのサインイン状態を起動時に確認しておく
                    // (未サインインならシステムがサインイン画面を出してくれる)。
                    GameCenterManager.shared.authenticate()
                }
        }
    }
}

/// タイトル画面→本編(RootTabView)、という起動の流れを管理する。
/// 【2026-09-13追加】「起動していきなりタブ画面になる」という指摘への対応。
/// タイトル画面を見た/見ていないは端末に保存しない(毎回の起動で必ず見せる)。
private struct AppRootView: View {
    @State private var hasPassedTitleScreen = false

    var body: some View {
        // 【UIテストの安定性のための判断】タイトル→本編の切り替えにクロスフェード
        // アニメーションを付けると、切り替わりの一瞬だけ両方のビューがアクセシビリティ
        // ツリー上に共存し、UIテストから見た時に同じ名前のボタンが複数見える
        // (例:タブの「ガチャ」ボタンが2つ検出される)不安定さにつながった。
        // 見た目のこだわりよりも「実際に動く」ことを優先し、即座に切り替える。
        if hasPassedTitleScreen {
            RootTabView()
        } else {
            TitleScreenView {
                hasPassedTitleScreen = true
            }
        }
    }
}
