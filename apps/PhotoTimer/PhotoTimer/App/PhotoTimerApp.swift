import SwiftUI

@main
struct PhotoTimerApp: App {
    // 【2026-09-04修正(指摘D対応)】
    // 以前はここ(アプリ起動時)で音声セッションを確保しっぱなしにしていたため、アプリを開いただけで
    // 他アプリ(音楽アプリ等)の再生が強制的に止まってしまう不具合があった。
    // 音声セッションの確保・解放は、実際に動画を再生する瞬間だけ(TimerController.swift)行うように変更した。

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
