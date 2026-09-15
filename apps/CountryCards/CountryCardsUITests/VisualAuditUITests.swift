import XCTest

final class VisualAuditUITests: XCTestCase {
    func testCaptureMajorRedesignScreens() throws {
        let app = launchPastTitleScreen(arguments: ["-uiTestReset"])
        XCTAssertTrue(app.buttons["tab_ホーム"].waitForExistence(timeout: 5))
        capture(app, "01-home")
        app.buttons["tab_図鑑"].tap(); capture(app, "02-collection")
        app.buttons["tab_ガチャ"].tap(); capture(app, "03-gacha")
        app.buttons["tab_対戦"].tap(); capture(app, "04-battle")
        app.buttons["対戦を始める"].tap(); capture(app, "05-battle-play")
    }


    func testRewardedAdCancelAndCompletion() throws {
        let app = launchPastTitleScreen(arguments: ["-uiTestRewardedAd"])
        XCTAssertTrue(app.buttons["tab_ガチャ"].waitForExistence(timeout: 5))
        app.buttons["tab_ガチャ"].tap()
        let acquire = app.buttons["rewardedAdAcquireButton"]
        XCTAssertTrue(acquire.waitForExistence(timeout: 5))

        acquire.tap()
        XCTAssertTrue(app.buttons["rewardedAdCancel"].waitForExistence(timeout: 3))
        app.buttons["rewardedAdCancel"].tap()
        XCTAssertTrue(acquire.waitForExistence(timeout: 3), "途中終了では権利も広告回数も変化しない")

        acquire.tap()
        XCTAssertTrue(app.buttons["rewardedAdComplete"].waitForExistence(timeout: 3))
        app.buttons["rewardedAdComplete"].tap()
        XCTAssertTrue(app.staticTexts["無料ガチャ残り 1回"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["gachaIntroArea"].exists, "視聴完了後も勝手にガチャを開始しない")
    }


    func testThreeHundredCardBatchSkipIsImmediate() throws {
        let app = launchPastTitleScreen(arguments: ["-uiTestBatchPoints", "-uiTestBatchStops"])
        XCTAssertTrue(app.buttons["tab_ガチャ"].waitForExistence(timeout: 5)); app.buttons["tab_ガチャ"].tap()
        app.buttons["ポイント"].tap()
        XCTAssertTrue(app.staticTexts["ポイントで引く"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pointElement_population"].waitForExistence(timeout: 5)); app.buttons["pointElement_population"].tap()
        XCTAssertTrue(app.buttons["100回引く(1000pt)"].waitForExistence(timeout: 5)); app.buttons["100回引く(1000pt)"].tap()
        XCTAssertTrue(app.buttons["batchSkipButton"].waitForExistence(timeout: 3)); app.buttons["batchSkipButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["batchResultSummary"].waitForExistence(timeout: 3), "300枚を1枚ずつ待たず一括結果へ移行する")
    }

    func testThirtyCardFastForwardStopsAtRareAndResumes() throws {
        let app = openPointBatch(arguments: ["-uiTestBatchPoints", "-uiTestBatchStops"], pullButton: "10回引く(100pt)")
        let intro = app.descendants(matching: .any)["batchIntroArea"]
        XCTAssertTrue(intro.waitForExistence(timeout: 3)); let started = Date(); intro.tap()
        let back = app.descendants(matching: .any)["batchRareCardBack"]
        XCTAssertTrue(back.waitForExistence(timeout: 2)); XCTAssertLessThan(Date().timeIntervalSince(started), 2, "N/SR高速区間が実時間で完了する")
        capture(app, "07-batch30-rare-back")
        XCTAssertFalse(app.staticTexts["UNKNOWN"].exists); back.tap()
        let face = app.descendants(matching: .any)["batchRareCardFace"]
        XCTAssertTrue(face.waitForExistence(timeout: 2))
        capture(app, "08-batch30-rare-face")
        XCTAssertTrue(face.waitForNonExistence(timeout: 3))
        XCTAssertTrue(back.waitForExistence(timeout: 5), "公開後に高速処理を再開し次のSSRで停止する")
        app.buttons["batchSkipButton"].tap(); XCTAssertTrue(app.descendants(matching: .any)["batchResultSummary"].waitForExistence(timeout: 2))
    }

    func testThreeHundredCardStopsAtMultipleRareCardsThenSkips() throws {
        let app = openPointBatch(arguments: ["-uiTestBatchPoints", "-uiTestBatchStops"], pullButton: "100回引く(1000pt)")
        app.descendants(matching: .any)["batchIntroArea"].tap()
        let back = app.descendants(matching: .any)["batchRareCardBack"]
        for _ in 0..<2 {
            XCTAssertTrue(back.waitForExistence(timeout: 3)); XCTAssertFalse(app.staticTexts["UNKNOWN"].exists); back.tap()
            XCTAssertTrue(app.descendants(matching: .any)["batchRareCardFace"].waitForExistence(timeout: 2)); XCTAssertTrue(back.waitForNonExistence(timeout: 2))
        }
        XCTAssertTrue(back.waitForExistence(timeout: 4), "300枚でも複数SSR+位置で停止する")
        capture(app, "09-batch300-third-stop")
        app.buttons["batchSkipButton"].tap(); XCTAssertTrue(app.descendants(matching: .any)["batchResultSummary"].waitForExistence(timeout: 2))
        capture(app, "10-batch300-result")
    }

    private func openPointBatch(arguments: [String], pullButton: String) -> XCUIApplication {
        let app = launchPastTitleScreen(arguments: arguments)
        XCTAssertTrue(app.buttons["tab_ガチャ"].waitForExistence(timeout: 5)); app.buttons["tab_ガチャ"].tap(); app.buttons["ポイント"].tap()
        XCTAssertTrue(app.buttons["pointElement_population"].waitForExistence(timeout: 5)); app.buttons["pointElement_population"].tap()
        XCTAssertTrue(app.buttons[pullButton].waitForExistence(timeout: 5)); app.buttons[pullButton].tap()
        return app
    }

    func testCaptureLandscapeWithAccessibilityText() throws {
        let app = launchPastTitleScreen(arguments: ["-uiTestReset", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityLarge"])
        XCTAssertTrue(app.buttons["tab_ホーム"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["tab_ガチャ"].waitForExistence(timeout: 5))
        capture(app, "06-landscape-accessibility-large")
        XCUIDevice.shared.orientation = .portrait
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
