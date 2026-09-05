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
            runLabelDiagnosticIfRequested()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                libraryManager.refreshAuthorizationStatus()
            }
        }
    }

    /// 【2026-09-05追加・調査専用】Visionの一般分類(VNClassifyImageRequest)が実際に
    /// どんなラベルをどれだけ返すかを実測するための呼び出し口。実測ロジック本体は
    /// DiagLabelMeasurement.swift(DEBUGビルド限定・検証後に削除予定)にある。
    /// これまでの「場所」診断(旧runLocationDiagnosticIfRequested。調査完了につき削除済み)と
    /// 全く同じ設計:普段の起動では何もしない(環境変数を明示的に渡した時だけ動く)・
    /// DEBUGビルド限定・読み取り専用・結果は件数集計のみをNSLogへ出す。
    private func runLabelDiagnosticIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["PHOTOTIMER_DIAG_LABELS"] == "1" else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            NSLog("[PhotoTimer][DiagLabels] 写真アクセスが許可されていないため計測できません")
            return
        }
        Task.detached(priority: .utility) {
            await DiagLabelMeasurement.run()
        }
        #endif
    }
}
