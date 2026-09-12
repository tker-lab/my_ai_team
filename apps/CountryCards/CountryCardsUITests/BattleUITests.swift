import XCTest

/// 対戦(CPU戦)が5ターン最後まで、人手のタップなしで進められるかを確認する。
final class BattleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBattleCanBePlayedToCompletion() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["対戦"].tap()
        let startButton = app.buttons["対戦を始める"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        // 5ターン、それぞれ「手札から1枚選ぶ→次へ」を繰り返す。
        for turn in 1...5 {
            // 手札のカード(CardView)はボタンとして並んでいるので、最初の1枚を選ぶ。
            let handCards = app.scrollViews.buttons
            XCTAssertTrue(handCards.element(boundBy: 0).waitForExistence(timeout: 5), "ターン\(turn): 手札が表示されること")
            handCards.element(boundBy: 0).tap()

            let nextButton = app.buttons["次へ"]
            XCTAssertTrue(nextButton.waitForExistence(timeout: 5), "ターン\(turn): 結果画面へ進むこと")
            nextButton.tap()
        }

        let resultText = app.staticTexts["対戦に勝利しました!"].firstMatch
        let loseText = app.staticTexts["対戦に敗北しました"].firstMatch
        XCTAssertTrue(resultText.waitForExistence(timeout: 5) || loseText.exists, "5ターン終了後、勝敗の結果画面が出ること")
    }
}
