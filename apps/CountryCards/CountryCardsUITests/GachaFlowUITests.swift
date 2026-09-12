import XCTest

/// ガチャの操作フロー(通常モード・スキップモード)が実際に動くかを、
/// 人手のタップなしで自動確認するテスト。PhotoTimerと同様の考え方で、
/// アプリ本体には手を加えずアクセシビリティIDだけを頼りに操作する。
final class GachaFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 通常モード:導入演出をタップで開始→カードを1枚ずつタップして見ていく。
    func testNormalModeRevealsThreeCards() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        app.tabBars.buttons["ガチャ"].tap()
        let entrance = app.buttons["gachaEntrance_population"]
        XCTAssertTrue(entrance.waitForExistence(timeout: 5))
        entrance.tap()

        // .accessibilityElement(children: .combine)でまとめた要素は、中身によって
        // StaticText扱いになったりOther扱いになったりするため、型を問わず
        // identifierだけで探す `.any` を使う。
        let introArea = app.descendants(matching: .any)["gachaIntroArea"]
        XCTAssertTrue(introArea.waitForExistence(timeout: 5), "導入演出エリアが出ていること")
        introArea.tap() // 映像再生開始

        let revealArea = app.descendants(matching: .any)["gachaRevealArea"]
        XCTAssertTrue(revealArea.waitForExistence(timeout: 5), "再生後にカード表示エリアへ切り替わること")

        // 3枚それぞれ「タップして表にする」「タップして次へ」の2タップずつ、計6タップ
        for _ in 0..<6 {
            revealArea.tap()
            usleep(300_000)
        }

        let againButton = app.buttons["もう一度引く"]
        XCTAssertTrue(againButton.waitForExistence(timeout: 5), "3枚見終わって結果画面に到達すること")
    }

    /// スキップモード:スキップボタンでN/SRは自動めくり、SSR以上でだけ止まることを確認する。
    /// (どのレア度が出るかは乱数なので、ここでは「スキップ後、一定時間内に結果画面か
    /// タップ待ち画面のどちらかに到達し、フリーズしないこと」を確認する)
    func testSkipModeDoesNotFreeze() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        app.tabBars.buttons["ガチャ"].tap()
        let entrance = app.buttons["gachaEntrance_gdp"]
        XCTAssertTrue(entrance.waitForExistence(timeout: 5))
        entrance.tap()

        let skipButton = app.buttons["gachaSkipButton"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
        skipButton.tap()

        // 自動めくり(N/SR)を待ちつつ、SSR以上で止まっていたらタップして進める。
        // 最大20回タップ試行して、いずれ結果画面に到達することを確認する。
        let againButton = app.buttons["もう一度引く"]
        var reachedResult = false
        for _ in 0..<20 {
            if againButton.exists {
                reachedResult = true
                break
            }
            let revealArea = app.descendants(matching: .any)["gachaRevealArea"]
            if revealArea.exists {
                revealArea.tap()
            }
            usleep(400_000)
        }
        XCTAssertTrue(reachedResult, "スキップモードでも最終的に結果画面へ到達すること(フリーズしないこと)")
    }
}
