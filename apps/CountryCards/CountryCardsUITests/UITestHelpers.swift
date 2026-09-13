import XCTest

/// UIテスト共通のヘルパー。
/// 【2026-09-13追加】起動画面(タイトル画面)が挟まるようになったため、
/// 既存のテスト群が正しく本編(タブ画面)へ到達できるよう、ここでタイトルを
/// タップして通過させる処理を1箇所にまとめる。
extension XCTestCase {
    /// 指定した起動引数でアプリを起動し、タイトル画面が出ていればタップして
    /// 通過させた状態で返す。各テストは従来どおり「本編に入った後」の確認に集中できる。
    func launchPastTitleScreen(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()

        let titleArea = app.descendants(matching: .any)["titleScreenTapArea"]
        if titleArea.waitForExistence(timeout: 5) {
            titleArea.tap()
        }
        return app
    }
}
