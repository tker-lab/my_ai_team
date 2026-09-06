import SwiftUI
import Photos

/// 写真アクセスの許可状況に応じて、許可依頼画面 or タイマー画面を出し分ける入り口。
struct RootView: View {
    @StateObject private var libraryManager = PhotoLibraryManager.shared
    /// アプリが今フォアグラウンド(画面に出ていて操作できる状態)か・バックグラウンドかを表す値。
    /// 【指摘D対応】設定アプリで許可を変更してこのアプリに戻ってきた場合、iOSはアプリを
    /// 終了させずそのまま復帰させることが多いため、`onAppear`(この画面が最初に現れた時)しか
    /// 見ていないと許可状況の再確認が起きず、「許可されていません」の画面のまま止まっていた
    /// (再起動しないと使えない不具合)。`scenePhase` を監視し、フォアグラウンドに戻るたびに
    /// 許可状況を再確認することで、設定アプリから戻った直後に画面が切り替わるようにする。
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if libraryManager.isUsable {
                ContentView()
            } else {
                PhotoAuthorizationView()
            }
        }
        .onAppear {
            libraryManager.refreshAuthorizationStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                libraryManager.refreshAuthorizationStatus()
            }
        }
        .themedTint()
        // 【テーマ機能追加(2026-09-06)にあたっての判断】このアプリは背景色までテーマで
        // 塗り替える方式のため、端末側のダークモードに任せると文字色(.primary等)だけが
        // 白反転してテーマの明るい背景に埋もれてしまう。テーマ自体が「配色を選ぶ」機能なので、
        // アプリ内は常に明るい配色で統一し、ダークモードの影響を受けないようにする。
        .preferredColorScheme(.light)
    }
}
