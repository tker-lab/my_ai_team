import XCTest

/// 起動画面(タイトル画面)が出て、タップすると本編に進めることを確認する。
final class TitleScreenUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTitleScreenLeadsToMainApp() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        let titleArea = app.descendants(matching: .any)["titleScreenTapArea"]
        XCTAssertTrue(titleArea.waitForExistence(timeout: 5), "起動直後にタイトル画面が出ること")
        XCTAssertFalse(app.tabBars.buttons["図鑑"].exists, "タイトル画面の間は本編(タブ)が出ていないこと")

        titleArea.tap()

        XCTAssertTrue(app.tabBars.buttons["図鑑"].waitForExistence(timeout: 5), "タップ後は本編(タブ)に進めること")
    }
}
