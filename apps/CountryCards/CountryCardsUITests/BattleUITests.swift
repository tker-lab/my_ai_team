import XCTest

/// 対戦(CPU戦)が5ターン最後まで、人手のタップなしで進められるかを確認する。
final class BattleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBattleCanBePlayedToCompletion() throws {
        let app = launchPastTitleScreen(arguments: ["-uiTestReset"])

        app.buttons["tab_対戦"].tap()
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
        var sawDraw = false
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
            for rarity in ["N", "SR", "SSR", "UR", "HUR"] {
                XCTAssertFalse(app.staticTexts[rarity].exists, "ターン\(turn): 対戦中にレア度 \(rarity) を表示しない")
            }
            for index in 0..<candidateButtons.count {
                let spoken = candidateButtons.element(boundBy: index).label.uppercased()
                XCTAssertFalse(["、N", "、SR", "、SSR", "、UR", "、HUR"].contains(where: spoken.contains), "VoiceOverラベルからレア度を漏らさない")
            }

            candidateButtons.element(boundBy: 0).tap()

            let nextButton = app.buttons["次へ"]
            XCTAssertTrue(nextButton.waitForExistence(timeout: 5), "ターン\(turn): 結果画面へ進むこと")
            // 決着後は「？？？」が消え、両者の数値が公開されているはず。
            XCTAssertFalse(app.staticTexts["？？？"].firstMatch.exists, "ターン\(turn): 決着後は数値が公開されること")

            // 【2026-09-14修正確認①】選ばなかった残り3枚の数値も、決着後に公開されること。
            // (見出し文言は2026-09-14に「選ばなかった手札の数値も公開」→「選ばなかった手札」に短縮)
            XCTAssertTrue(
                app.staticTexts["選ばなかった手札"].waitForExistence(timeout: 5),
                "ターン\(turn): 選ばなかった3枚の数値も公開されること"
            )

            // 【2026-09-14修正確認②】引き分け表示そのものが選択肢として機能している
            // ことを確認する(実際に同値が出た時にちゃんと「引き分け」になっているかは
            // 下のDRAWバッジ確認で見る)。
            let drawLabel = app.staticTexts["このターンは引き分け"]
            let winLabel = app.staticTexts["このターンはあなたの勝ち!"]
            let loseLabel = app.staticTexts["このターンはCPUの勝ち"]
            XCTAssertTrue(
                drawLabel.exists || winLabel.exists || loseLabel.exists,
                "ターン\(turn): 勝ち/負け/引き分けのいずれかが表示されること"
            )
            if drawLabel.exists {
                sawDraw = true
                XCTAssertTrue(app.staticTexts["DRAW"].firstMatch.exists, "ターン\(turn): 引き分け時は両カードにDRAW表示が出ること")
            }

            nextButton.tap()
        }

        let winText = app.staticTexts["対戦に勝利しました!"].firstMatch
        let loseText = app.staticTexts["対戦に敗北しました"].firstMatch
        let drawText = app.staticTexts["対戦は引き分けでした"].firstMatch
        // 【2026-09-14仕様】5ターン終えた結果、試合トータルが引き分けになるのも
        // 問題ない仕様として許容する(無理に決着を付けない)。
        XCTAssertTrue(
            winText.waitForExistence(timeout: 5) || loseText.exists || drawText.exists,
            "5ターン終了後、勝敗(または引き分け)の結果画面が出ること"
        )
        if sawDraw {
            // ラウンドの引き分けが実際に発生した実行では、ログにも残しておく
            // (毎回は起きないため、CIで再現しなくても失敗にはしない)。
            print("[BattleUITests] このテスト実行ではラウンドの引き分けが発生した")
        }
    }
}
