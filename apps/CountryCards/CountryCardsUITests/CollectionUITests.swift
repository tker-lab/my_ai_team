import XCTest

/// 図鑑(コレクション)画面の基本表示が落ちずに動くかを確認する。
final class CollectionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCountryListAndDetailDoNotCrash() throws {
        let app = XCUIApplication()
        app.launch()

        // 起動直後は図鑑タブ(国別)が表示されているはず。「図鑑」という
        // タイトルの一覧画面から、詳細画面(タイトルが変わる)へ遷移できることを確認する。
        let listTitle = app.navigationBars["図鑑"]
        XCTAssertTrue(listTitle.waitForExistence(timeout: 5))

        // cells[0]は「国連加盟193カ国のみ対象」という注意書きの行なので、
        // 実際に国が並ぶcells[1]をタップする。
        let firstCell = app.cells.element(boundBy: 1)
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
        firstCell.tap()

        // 詳細画面ではナビゲーションタイトルが国名に変わっているはず(「図鑑」ではなくなる)。
        let detailAppeared = NSPredicate(format: "identifier != %@", "図鑑")
        let detailTitle = app.navigationBars.matching(detailAppeared).firstMatch
        XCTAssertTrue(detailTitle.waitForExistence(timeout: 5), "国の詳細画面へ遷移すること")

        app.navigationBars.firstMatch.buttons.firstMatch.tap() // 戻る
        XCTAssertTrue(listTitle.waitForExistence(timeout: 5), "一覧画面に戻れること")

        // 「要素別」に切り替えて、要素のランキング画面まで開けること。
        app.buttons["要素別"].tap()
        let firstElementCell = app.cells.element(boundBy: 1)
        XCTAssertTrue(firstElementCell.waitForExistence(timeout: 5))
        firstElementCell.tap()
        let elementDetailTitle = app.navigationBars.matching(detailAppeared).firstMatch
        XCTAssertTrue(elementDetailTitle.waitForExistence(timeout: 5), "要素のランキング画面へ遷移すること")
    }
}
