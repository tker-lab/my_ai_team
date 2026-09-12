import XCTest

/// 図鑑(コレクション)画面の基本表示が落ちずに動くかを確認する。
final class CollectionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCountryListAndDetailDoNotCrash() throws {
        let app = XCUIApplication()
        app.launch()

        // 起動直後は図鑑タブ(国別)が表示されているはず。
        let firstCell = app.cells.element(boundBy: 0)
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        firstCell.tap()

        // 国の詳細画面へ遷移し、要素カード(グリッド)が何か表示されること。
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap() // 戻る

        // 「要素別」に切り替えて、要素のランキング画面まで開けること。
        app.buttons["要素別"].tap()
        let firstElementCell = app.cells.element(boundBy: 0)
        XCTAssertTrue(firstElementCell.waitForExistence(timeout: 5))
        firstElementCell.tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 5))
    }
}
