import SwiftUI
import AVFAudio

@main
struct PhotoTimerApp: App {
    init() {
        // 動画の音を再生するため、サイレントスイッチが「消音」でも音が出るモードにする。
        // (写真アプリのスライドショーや動画プレイヤーと同じ挙動。仮の判断:詳細は報告参照)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
