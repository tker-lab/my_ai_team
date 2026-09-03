import SwiftUI

/// 写真アクセスの許可状況に応じて、許可依頼画面 or タイマー画面を出し分ける入り口。
struct RootView: View {
    @StateObject private var libraryManager = PhotoLibraryManager.shared

    var body: some View {
        Group {
            if libraryManager.isUsable {
                ContentView()
            } else {
                PhotoAuthorizationView()
            }
        }
        .onAppear { libraryManager.refreshAuthorizationStatus() }
    }
}
