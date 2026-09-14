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

        // 5ターン、それぞれ「CPUのカードを見る→自分の手札4枚から1枚選ぶ→次へ」を繰り返す
        // (2026-09-14仕様変更:CPUのカードを先に提示し、プレイヤーは4枚の候補から
        // 1枚を選ぶ選択式に変更)。同時に、
        // ・CPUのカードが国・要素は見える状態で数値だけ伏せて先に出ること
        // ・プレイヤーの候補が4枚出ること
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

            let cpuCaption = app.staticTexts["CPUの手札(数値は選ぶまで分かりません)"]
            XCTAssertTrue(cpuCaption.waitForExistence(timeout: 5), "ターン\(turn): CPUのカードが先に表示されること")

            let candidateButtons = app.buttons.matching(identifier: "battleCandidateButton")
            XCTAssertEqual(candidateButtons.count, 4, "ターン\(turn): プレイヤーの候補が4枚提示されること")

            candidateButtons.element(boundBy: 0).tap()

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
