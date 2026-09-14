import XCTest

/// 図鑑(コレクション)画面の基本表示が落ちずに動くかを確認する。
final class CollectionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCountryListAndDetailDoNotCrash() throws {
        let app = launchPastTitleScreen(arguments: ["-uiTestReset"])

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

    /// 【2026-09-14 バグ修正の確認】CO2排出量データが無くカードが9種類しか
    /// 存在しない国(モナコ)は、9枚集め切った時点で豆知識10個全部が解放される
    /// はず(修正前は固定分母10のままだったため、9枚では永遠に10個目が
    /// 解放されなかった)。
    func testNineCardCountryUnlocksAllTenTrivia() throws {
        let app = launchPastTitleScreen(arguments: ["-uiTestSeedNineCardCountry"])

        let listTitle = app.navigationBars["図鑑"]
        XCTAssertTrue(listTitle.waitForExistence(timeout: 5))

        // 国名「モナコ」の行を探してタップする(一覧の並び順に依存しないように
        // インデックスではなく表示文字列で探す)。193カ国中107番目あたりにいるため、
        // 一覧は仮想化されており(画面外の行はアクセシビリティツリーに無い)、
        // 見つかるまで下にスクロールする必要がある。
        let monacoCell = app.staticTexts["モナコ"]
        let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        var attempts = 0
        while !monacoCell.exists, attempts < 40 {
            list.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(monacoCell.waitForExistence(timeout: 5), "モナコの行が一覧にあること(スクロール後)")
        monacoCell.tap()

        let detailTitle = app.navigationBars["モナコ"]
        XCTAssertTrue(detailTitle.waitForExistence(timeout: 5), "モナコの詳細画面へ遷移すること")

        // 豆知識の見出しが「10/10 解放」になっている(分母が実カード枚数の9ではなく
        // 固定10になっていて、かつ9枚全部集めた時点で10個とも解放されている)ことを確認する。
        let unlockedHeader = app.staticTexts["豆知識(10/10 解放)"]
        XCTAssertTrue(unlockedHeader.waitForExistence(timeout: 5), "9枚集め切ったら10/10と表示されること")

        // 鍵アイコン付きの「まだ解放されていません」系の行が残っていないことも確認する。
        let lockedRow = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "集めると解放されます")).firstMatch
        XCTAssertFalse(lockedRow.exists, "10個とも解放済みで、鍵付きの行が残っていないこと")
    }
}
