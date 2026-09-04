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
            runLocationDiagnosticIfRequested()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                libraryManager.refreshAuthorizationStatus()
            }
        }
    }

    /// 【2026-09-04追加・調査専用】「場所」の絞り込みが「位置情報付きの写真が見つかりませんでした」に
    /// なる件の事実確認のためだけの診断コード。
    ///
    /// CEOの実機で「本当に位置情報付きの写真が無いのか」「実装側が読み取れていないだけなのか」を
    /// 切り分けるために追加した。普段の起動では何もしない(下記の環境変数を明示的に渡した時だけ動く)。
    /// - CEOが普段アプリを使う時に動くことは無い(環境変数は開発者がXcode/devicectl経由で明示的に
    ///   渡さない限りセットされない)。
    /// - DEBUGビルドのみに存在するコードで、リリース版には含まれない。
    /// - 何をするか:写真ライブラリ全体を1回だけ数え、「位置情報付きの枚数/全体の枚数」と
    ///   写真アクセス許可の状態をコンソールログ(NSLog)に出すだけ。結果は端末内のログに残るのみで、
    ///   外部へは一切送信しない。CEOの写真そのもの(画像データ)は見ない・保存しない。
    /// - 通常のスキャン(原則4)には影響しない。ここでの全件列挙は診断専用の一度きりの処理で、
    ///   LibraryIndex側の「場所」データ(place_clusters.json 等)には一切書き込まない。
    private func runLocationDiagnosticIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["PHOTOTIMER_DIAG_LOCATION"] == "1" else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        NSLog("[PhotoTimer][Diag] authorizationStatus=\(status.rawValue) (0=notDetermined,1=restricted,2=denied,3=authorized,4=limited)")
        guard status == .authorized || status == .limited else {
            NSLog("[PhotoTimer][Diag] 写真アクセスが許可されていないため件数を数えられません")
            return
        }
        Task.detached(priority: .utility) {
            let fetchResult = PHAsset.fetchAssets(with: nil)
            var total = 0
            var withLocation = 0
            var photoWithLocation = 0
            var videoWithLocation = 0
            fetchResult.enumerateObjects { asset, _, _ in
                total += 1
                if asset.location != nil {
                    withLocation += 1
                    if asset.mediaType == .video { videoWithLocation += 1 } else { photoWithLocation += 1 }
                }
            }
            NSLog("[PhotoTimer][Diag] total=\(total) withLocation=\(withLocation) (photo=\(photoWithLocation) video=\(videoWithLocation))")
        }
        #endif
    }
}
