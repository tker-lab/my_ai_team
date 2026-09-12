import XCTest

/// 初回起動時にユーザー名を決めるまで本編に進めないことを確認する
/// (チェック工程指摘 #5 への対応)。
final class OnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMustEnterNameBeforeReachingMainApp() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestResetNoUsername"]
        app.launch()

        // 名前を入力するまでは、タブバー(本編)にたどり着けないこと。
        let nameField = app.textFields["onboardingNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "起動直後に名前入力画面が出ること")
        // fullScreenCoverの裏にあるTabViewはツリー上には残ることがあるため、
        // 「見えている(タップ可能)かどうか」で覆われていることを確認する。
        XCTAssertFalse(app.tabBars.buttons["図鑑"].isHittable, "名前入力前はタブバーが操作できないこと")

        let startButton = app.buttons["onboardingStartButton"]
        XCTAssertFalse(startButton.isEnabled, "名前が空の間は「はじめる」が押せないこと")

        nameField.tap()
        nameField.typeText("たろう")
        XCTAssertTrue(startButton.isEnabled)
        startButton.tap()

        XCTAssertTrue(app.tabBars.buttons["図鑑"].waitForExistence(timeout: 5), "名前を決めた後は本編(タブバー)に進めること")
    }
}
