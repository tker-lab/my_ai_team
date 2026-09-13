import XCTest

/// 対戦(CPU戦)が5ターン最後まで、人手のタップなしで進められるかを確認する。
final class BattleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBattleCanBePlayedToCompletion() throws {
        let app = launchPastTitleScreen(arguments: ["-uiTestReset"])

        app.tabBars.buttons["対戦"].tap()
        let startButton = app.buttons["対戦を始める"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        // 5ターン、それぞれ「対戦する→次へ」を繰り返す
        // (2026-09-13仕様変更:デッキ廃止によりカードは自動で決まるため、
        // 手札から選ぶ操作は無くなった)。同時に、
        // ・決着前は数値が「？？？」で伏せられていること
        // ・5ターンとも異なるお題(要素)であること
        // も確認する。
        var seenTopics: Set<String> = []
        for turn in 1...5 {
            let topicText = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "お題:")).firstMatch
            XCTAssertTrue(topicText.waitForExistence(timeout: 5), "ターン\(turn): お題が表示されること")
            let topic = topicText.label
            XCTAssertFalse(seenTopics.contains(topic), "ターン\(turn): 同じお題が2回出ていないこと(出たお題: \(seenTopics))")
            seenTopics.insert(topic)

            XCTAssertTrue(app.staticTexts["？？？"].firstMatch.exists, "ターン\(turn): 対戦前は数値が伏せられていること")

            let fightButton = app.buttons["battleFightButton"]
            XCTAssertTrue(fightButton.waitForExistence(timeout: 5), "ターン\(turn): 対戦するボタンが表示されること")
            fightButton.tap()

            let nextButton = app.buttons["次へ"]
            XCTAssertTrue(nextButton.waitForExistence(timeout: 5), "ターン\(turn): 結果画面へ進むこと")
            // 決着後は「？？？」が消え、両者の数値が公開されているはず。
            XCTAssertFalse(app.staticTexts["？？？"].firstMatch.exists, "ターン\(turn): 決着後は数値が公開されること")
            nextButton.tap()
        }

        let resultText = app.staticTexts["対戦に勝利しました!"].firstMatch
        let loseText = app.staticTexts["対戦に敗北しました"].firstMatch
        XCTAssertTrue(resultText.waitForExistence(timeout: 5) || loseText.exists, "5ターン終了後、勝敗の結果画面が出ること")
    }
}
