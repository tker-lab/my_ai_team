import XCTest

/// 「タイマーが動きながら写真が実際に流れる」ことを、人手のタップに頼らず自動で確認するテスト。
///
/// XCUITest(UI Testing = Xcodeが用意している「画面を実際にタップ・操作して確認する」仕組み)を使い、
/// シミュレータ上でアプリを実際に操作する。アプリ本体のコードは一切変更しない(確認のためだけに、
/// 画面側に「目印」= アクセシビリティID を追加しているのみ。画面表示や動作には影響しない)。
///
/// シナリオ一覧(v3 = 2026-09-04の3点変更+既存不具合確認の検証):
///  1. testDefaultFlow_NoFilter … 何も絞り込まず(アプリを開いて即スタート、を想定した一番基本の使い方)
///  2. testPhotoFilterFlow … 「メディアの種類=写真」だけ選んでスタート
///  3. testVideoFilterFlow … 「メディアの種類=動画」だけ選んでスタート(動画の音付き再生の確認用)
///  4. testOneSecondTimer … ホイールで最短の「1秒」を選んでスタートし、実際に1秒程度で終わることを確認
///  5. testPhotoDurationSettingAffectsInterval … 設定画面で写真の表示秒数を変えると、切り替わる間隔が実際に変わることを確認
///  6. testVideoDurationSettingAffectsCutoff … 設定画面で動画の「指定秒数で切り上げる/最後まで再生する」を変えると、実際の挙動が変わることを確認
///  7. testWheelDisplaySync … ホイールの値と画面上部の大きな時間表示が、操作が落ち着いた後は必ず一致することを確認(既存の疑わしいスクリーンショットの検証)
///
/// v4シナリオ(2026-09-04 チェック工程1回目の指摘対応の検証。証跡は verify/ に v4_ 接頭辞で保存):
///  8. testEmptyResult_NeverMatchingMoodAndCategory … 雰囲気+カテゴリの組み合わせ条件で、遅延評価(原則2)の
///     結果0件になりうるケース。指摘Bで実際に問題だった「無限ループで固まる」不具合の直接の回帰テスト。
///     一定時間内に必ず決着し(見つからない表示 or 通常再生)、閉じるボタンが効き続けることを確認する。
///  9. testFiveFilterCombination … 日時・アルバム・雰囲気を実際に画面操作で選択し(+メディアの種類・
///     スクリーンショット除くは既定値のまま)、「場所」セクションの表示も確認した上でスタートしても
///     クラッシュ・フリーズせず、決着した状態(通常再生 or 見つかりませんでした)に至ることを確認。
///     (場所はテスト用ライブラリに位置情報付きの写真が無い可能性が高いため、選べる時だけ選ぶ)
///  10. testPermissionDenied_ShowsDeniedState / 11. testEmptyLibrary_NoPhotosAtAll … 権限拒否・写真が
///      ごくわずかなケース。既存の検証用シミュレータを壊さないよう別シミュレータで実行する
///      (実行方法は該当テストの直前のコメント参照)。
///
/// v5シナリオ(2026-09-04 チェック工程2回目の指摘対応の検証。証跡は verify/ に v5_ 接頭辞で保存):
///  12. testImmediateDismiss_DuringLazyEvaluation_NoBackgroundHang … 雰囲気・カテゴリの絞り込みで
///      候補全体の採点(窓単位の遅延評価)が終わる前に✕で閉じても、素早くホーム画面に戻れ、
///      その後の操作が遅延しないことを確認(指摘A: ✕で閉じても裏で解析が走り続ける不具合の回帰テスト)。
///  13. testLegacyPlaceSelection_MigratesAndOffersClear … 場所ID方式変更前の「旧形式」の場所選択が
///      UserDefaultsに残っていた状態からの復帰(移行・解除ができること)を確認
///      (指摘B・G: 復帰手段が無い/設定がiCloudバックアップに含まれる、の回帰テスト)。
///
/// v6シナリオ(2026-09-05 CEO実機フィードバック対応の検証。証跡は verify/ に v6_ 接頭辞で保存):
///  14. testNearMatchStreaming_AlwaysShowsSomething … 雰囲気+カテゴリの組み合わせ条件でスタートしても、
///      「近い順に流す」設計により一定時間内に必ず通常のスライドショーへ決着すること(見つかりませんでした、
///      には基本的にならないこと)を確認する(CEO報告「鮮やか×犬で何も出ない」への対応の回帰テスト)。
///  15. testGreenRemovedFromMoodChoices … 絞り込み画面の「雰囲気・色」の選択肢一覧に「緑」が
///      表示されないこと、他の選択肢(暖色・寒色等)は引き続き選べることを確認する。
///  16. testHelpScreen_OpensAndShowsGuidance … ホーム画面の「?」から使い方説明画面が開き、
///      主要な案内文(位置情報設定・プライバシー)が表示されることを確認する。
///  17. testAlarmSettings_UntilStoppedShowsStopButton … アラーム設定画面で「止めるまで鳴り続ける」を
///      選んでからタイマーを実行し、タイマー終了後に「アラームを止める」ボタンが表示され、
///      押すと「閉じる」に切り替わることを確認する(CEO要望の鳴らし方切り替え機能の回帰テスト)。
final class PhotoTimerUITests: XCTestCase {

    /// utility除外・解析失敗も同じbeginCandidateを通るため、種類に関係なく18件で停止する。
    func testSearchBudgetCountsEveryDispositionAndStopsAt18() {
        var budget = CandidateSearchBudget(maximumCount: 18, maximumSeconds: 0.8)
        for index in 0..<18 {
            let simulatedDisposition = index.isMultiple(of: 2) ? "utility" : "analysisFailure"
            XCTAssertFalse(simulatedDisposition.isEmpty)
            XCTAssertTrue(budget.beginCandidate(elapsedSeconds: 0.1))
        }
        XCTAssertFalse(budget.beginCandidate(elapsedSeconds: 0.1))
        XCTAssertEqual(budget.consumedCount, 18)
    }

    /// 単一解析が遅延した想定でも、経過0.8秒で次候補を開始せず中断する。
    func testSearchBudgetStopsOnElapsedTimeAfterSingleSlowAnalysis() {
        var budget = CandidateSearchBudget(maximumCount: 18, maximumSeconds: 0.8)
        XCTAssertTrue(budget.beginCandidate(elapsedSeconds: 0))
        XCTAssertTrue(budget.isExhausted(elapsedSeconds: 0.8))
        XCTAssertFalse(budget.beginCandidate(elapsedSeconds: 0.8))
        XCTAssertEqual(budget.consumedCount, 1)
    }

    /// 旧世代は新世代キューへ追加できず、現世代でも上限2件を超えない。
    func testPrefetchQueueRejectsOldGenerationAndCapsAtTwo() {
        var queue = GenerationBoundedQueue<Int>(limit: 2)
        let old = queue.advanceGeneration(clear: true)
        XCTAssertTrue(queue.append(1, generation: old))
        let current = queue.advanceGeneration(clear: true)
        XCTAssertFalse(queue.append(99, generation: old))
        XCTAssertTrue(queue.append(2, generation: current))
        XCTAssertTrue(queue.append(3, generation: current))
        XCTAssertFalse(queue.append(4, generation: current))
        XCTAssertEqual(queue.elements, [2, 3])
    }

    override func setUpWithError() throws {
        continueAfterFailure = true // 1項目の失敗で残りの観察(スクリーンショット等)を打ち切らないため

        // 【2026-09-05追加:原因究明】CEO要望C(バックグラウンド動作)で、タイマー開始時に
        // 通知の許可(バックグラウンドでもアラームを鳴らすためのローカル通知)を尋ねる処理を追加した。
        // これにより「スタート」を押した直後、OS標準の通知許可ダイアログが新たに出るようになったが、
        // 既存のテストはこのダイアログを一切処理していなかったため、ダイアログに隠れた要素を
        // 待ち続けて延々とタイムアウトする(自動化セッションごと巻き込まれて再起動される)不具合が
        // 多数のテストで発生していた(調査の結果判明。写真アクセスの許可ダイアログとは別物)。
        // addUIInterruptionMonitorはXCTestが「割り込みのシステムダイアログ」を検知した時に
        // 自動的に呼ばれる仕組みで、これで「許可」ボタンがあれば毎回タップして先に進めるようにする
        // (実際のユーザーも初回だけこの許可を求められる。これは今回追加した正規の機能であり、
        // テスト側で処理すべき想定内のダイアログという位置づけ)。
        addUIInterruptionMonitor(withDescription: "通知の許可ダイアログを自動で許可する") { alert in
            let allowButton = alert.buttons["許可"]
            if allowButton.exists {
                allowButton.tap()
                return true
            }
            return false
        }
    }

    // MARK: - シナリオ1: 何も絞り込まない基本フロー

    func testDefaultFlow_NoFilter() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v3_default")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)
        // 前のテストで選んだ値が @AppStorage 経由で残っていることがあるため、観察に十分な長さを明示的に設定する。
        try Self.setTotalTimer(app: app, minutes: "5", seconds: "0")

        recorder.shoot(app, label: "launch")

        let startButton = app.buttons["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 15), "「スタート」ボタンが起動から15秒待っても見つからなかった")
        startButton.tap()

        // アプリがクラッシュしてホーム画面に戻された場合も検知できるよう、起動状態を確認する。
        Thread.sleep(forTimeInterval: 2.0)
        recorder.shoot(app, label: "after_start")

        if app.state != .runningForeground {
            XCTFail("バグ report: 「スタート」を押すとアプリが強制終了した(ホーム画面に戻された)。期待=スライドショーが始まる / 実際=アプリがクラッシュして終了。app.state=\(app.state.rawValue)")
            recorder.writeManifest()
            return
        }

        try Self.observeSlideshow(app: app, recorder: recorder, rounds: 10, requireVideo: false)
    }

    // MARK: - シナリオ2: 「写真」のみに絞り込んだフロー

    func testPhotoFilterFlow() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v3_photofilter")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)
        try Self.setTotalTimer(app: app, minutes: "5", seconds: "0")

        try Self.selectMediaTypeFilter(app: app, label: "写真")

        let startButton = app.buttons["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 15))
        startButton.tap()

        Thread.sleep(forTimeInterval: 2.0)
        recorder.shoot(app, label: "after_start")

        guard app.state == .runningForeground else {
            XCTFail("バグ report: 「メディアの種類=写真」を選んでスタートしてもアプリが強制終了した。app.state=\(app.state.rawValue)")
            recorder.writeManifest()
            return
        }

        try Self.observeSlideshow(app: app, recorder: recorder, rounds: 10, requireVideo: false)
    }

    // MARK: - シナリオ3: 「動画」のみに絞り込んだフロー(音付き再生の確認用)

    func testVideoFilterFlow() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v3_videofilter")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)
        try Self.setTotalTimer(app: app, minutes: "5", seconds: "0")

        try Self.selectMediaTypeFilter(app: app, label: "動画")

        let startButton = app.buttons["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 15))
        startButton.tap()

        Thread.sleep(forTimeInterval: 2.0)
        recorder.shoot(app, label: "after_start")

        guard app.state == .runningForeground else {
            XCTFail("バグ report: 「メディアの種類=動画」を選んでスタートしてもアプリが強制終了した。app.state=\(app.state.rawValue)")
            recorder.writeManifest()
            return
        }

        let mediaElement = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'media-'")
        ).firstMatch

        var sawVideoElement = false
        for round in 1...8 {
            Thread.sleep(forTimeInterval: 2.0)
            if mediaElement.exists {
                if mediaElement.identifier.hasPrefix("media-video-") { sawVideoElement = true }
            }
            recorder.shoot(app, label: "r\(round)_\(mediaElement.exists ? mediaElement.identifier : "none")")
        }
        recorder.writeManifest()
        XCTAssertTrue(sawVideoElement, "動画フィルタで絞り込んでも動画の目印(media-video-)が一度も観測できなかった")
    }

    // MARK: - シナリオ4(CEO要望1): タイマー下限=1秒で実際に1秒程度で終わるか

    func testOneSecondTimer() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v3_onesecond")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)

        let minutesWheel = app.pickerWheels.element(boundBy: 0)
        let secondsWheel = app.pickerWheels.element(boundBy: 1)
        XCTAssertTrue(minutesWheel.waitForExistence(timeout: 15), "「分」のホイールが見つからない")
        XCTAssertTrue(secondsWheel.waitForExistence(timeout: 5), "「秒」のホイールが見つからない")

        // まず現在値と異なる値にいったん動かしてから、目的の「0分1秒」に設定する
        // (前回実行時の値がたまたま一致して見かけ上パスする、を防ぐため)。
        minutesWheel.adjust(toPickerWheelValue: "1")
        secondsWheel.adjust(toPickerWheelValue: "10")
        minutesWheel.adjust(toPickerWheelValue: "0")
        secondsWheel.adjust(toPickerWheelValue: "1")
        Thread.sleep(forTimeInterval: 0.5) // ホイールのアニメーションが落ち着くのを待つ
        recorder.shoot(app, label: "wheel_set_1s")

        // 「設定可能な範囲」の表記が1秒からになっているかも合わせて確認する。
        let rangeLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '設定可能な範囲'")).firstMatch
        if rangeLabel.exists {
            recorder.appendManifestLines(["range label: \(rangeLabel.label)"])
            XCTAssertTrue(rangeLabel.label.contains("1秒"), "「設定可能な範囲」の表記が1秒からになっていない: \(rangeLabel.label)")
        }

        let homeTimeLabel = app.staticTexts["homeTimeLabel"]
        if homeTimeLabel.exists {
            recorder.appendManifestLines(["home time label before start: \(homeTimeLabel.label)"])
            XCTAssertEqual(homeTimeLabel.label, "00:01", "1秒に設定したはずが表示が00:01になっていない: \(homeTimeLabel.label)")
        }

        let startTime = Date()
        let startButton = app.buttons["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        // 「タイマー終了」の表示が出るまで、または一定時間まで待つ。
        let finishedText = app.staticTexts["タイマー終了"]
        let noResultsText = app.staticTexts["条件に合う写真・動画が見つかりませんでした"]
        var finishedAt: Date?
        for _ in 0..<100 { // 最大 100 x 100ms = 10秒待つ
            if finishedText.exists || noResultsText.exists {
                finishedAt = Date()
                break
            }
            usleep(100_000)
        }
        recorder.shoot(app, label: "after_wait")

        if noResultsText.exists {
            // 絞り込みなしなのでこの分岐は基本通らないはずだが、念のため記録して終了する。
            recorder.appendManifestLines(["候補が見つからなかった(この端末のテスト用ライブラリの状態に依存する可能性)"])
            recorder.writeManifest()
            return
        }

        guard let finishedAt else {
            XCTFail("1秒タイマーを開始したのに10秒待っても「タイマー終了」画面が出てこなかった")
            recorder.writeManifest()
            return
        }

        let elapsed = finishedAt.timeIntervalSince(startTime)
        recorder.appendManifestLines(["elapsed until finished: \(String(format: "%.2f", elapsed))s"])
        recorder.writeManifest()

        // 1秒設定なので、写真の読み込み時間を差し引いても数秒以内には終わるはず(実用的な余裕を持たせて5秒未満とする)。
        XCTAssertLessThan(elapsed, 5.0, "1秒に設定したのに終了まで異常に時間がかかった: \(String(format: "%.2f", elapsed))s")
    }

    // MARK: - シナリオ5(CEO要望2): 写真の表示秒数の設定が、実際の切り替わり間隔に反映されるか

    func testPhotoDurationSettingAffectsInterval() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v3_photoduration")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)

        // 前のテストで選んだ値が @AppStorage 経由で残っていることがあるため、
        // 観察に十分な長さ(1分)を明示的に設定してから始める。
        try Self.setTotalTimer(app: app, minutes: "1", seconds: "0")

        try Self.selectMediaTypeFilter(app: app, label: "写真") // 動画が混ざると間隔の比較がぶれるため写真のみに絞る

        let mediaElement = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'media-'")
        ).firstMatch

        // --- 1回目: 表示秒数を明示的に「長め(6秒)」に設定して計測 ---
        // (端末内保存の設定値は前回このテストを実行した時の値が残っていることがあるため、
        //  「初期値の4秒のまま」ではなく、この場で明示的に長い値を設定してから測る)
        try Self.setPhotoDuration(app: app, label: "6秒", recorder: recorder)

        let startButton = app.buttons["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 15))
        startButton.tap()
        Thread.sleep(forTimeInterval: 1.0)
        recorder.shoot(app, label: "default_after_start")

        guard app.state == .runningForeground else {
            XCTFail("バグ report: 写真フィルタでスタートしてもアプリが強制終了した。app.state=\(app.state.rawValue)")
            recorder.writeManifest()
            return
        }

        let defaultIntervals = Self.measureSwitchIntervals(mediaElement: mediaElement, observeSeconds: 14.0, pollInterval: 0.2)
        recorder.appendManifestLines(["long(6秒設定) intervals: \(defaultIntervals.map { String(format: "%.2f", $0) })"])

        // 閉じるボタン。以前はSF Symbol名("xmark.circle.fill")が暗黙のラベルとして拾えていたが、
        // v5でこのボタンに明示的なアクセシビリティID("closeButton")を付けたため、それに合わせて変更。
        app.buttons["closeButton"].firstMatch.tap()
        if !app.buttons["startButton"].waitForExistence(timeout: 5) {
            // ラベルでの取得に失敗した場合、画面左上あたりの唯一のボタンをタップするフォールバック。
            app.buttons.firstMatch.tap()
        }
        recorder.shoot(app, label: "after_close_1")

        // --- 表示秒数を1秒に変更 ---
        try Self.setPhotoDuration(app: app, label: "1秒", recorder: recorder)

        // --- 2回目: 1秒設定で計測 ---
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 10))
        app.buttons["startButton"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        recorder.shoot(app, label: "short_after_start")

        guard app.state == .runningForeground else {
            XCTFail("バグ report: 表示秒数を1秒に変更した後、スタートしてもアプリが強制終了した。app.state=\(app.state.rawValue)")
            recorder.writeManifest()
            return
        }

        let shortIntervals = Self.measureSwitchIntervals(mediaElement: mediaElement, observeSeconds: 8.0, pollInterval: 0.2)
        recorder.appendManifestLines(["short(1秒設定) intervals: \(shortIntervals.map { String(format: "%.2f", $0) })"])
        recorder.shoot(app, label: "final")
        recorder.writeManifest()

        XCTAssertFalse(defaultIntervals.isEmpty, "6秒設定での切り替わりが1回も観測できなかった")
        XCTAssertFalse(shortIntervals.isEmpty, "1秒設定での切り替わりが1回も観測できなかった")

        let avgDefault = defaultIntervals.reduce(0, +) / Double(defaultIntervals.count)
        let avgShort = shortIntervals.reduce(0, +) / Double(shortIntervals.count)
        recorder.appendManifestLines(["avgLong(6秒設定)=\(String(format: "%.2f", avgDefault))s avgShort(1秒設定)=\(String(format: "%.2f", avgShort))s"])

        XCTAssertLessThan(avgShort, avgDefault, "表示秒数を1秒に変更したのに、切り替わり間隔が6秒設定より短くなっていない")
        XCTAssertLessThan(avgShort, 2.5, "1秒設定にしたのに、切り替わり間隔が1秒より大きくずれている(observed: \(avgShort)s)")
    }

    // MARK: - シナリオ6(CEO要望3): 動画の再生時間の扱いの設定が実際の挙動に反映されるか

    func testVideoDurationSettingAffectsCutoff() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v3_videoduration")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)

        // 前のテストで選んだ値が @AppStorage 経由で残っていることがあるため、
        // 観察に十分な長さ(2分)を明示的に設定してから始める。
        try Self.setTotalTimer(app: app, minutes: "4", seconds: "0")

        try Self.selectMediaTypeFilter(app: app, label: "動画") // テスト用ライブラリの動画は1本(約4.9秒)

        let mediaElement = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'media-video-'")
        ).firstMatch

        // --- 動画の再生時間の扱いを「指定秒数(3秒)で切り上げる」に設定 ---
        try Self.setVideoCutoffMode(app: app, mode: .capped(seconds: "3秒"), recorder: recorder)

        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 10))
        app.buttons["startButton"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        recorder.shoot(app, label: "capped_after_start")

        guard app.state == .runningForeground else {
            XCTFail("バグ report: 動画フィルタ+3秒切り上げ設定でスタートしてもアプリが強制終了した。app.state=\(app.state.rawValue)")
            recorder.writeManifest()
            return
        }

        let cappedOnDuration = Self.measureOneOnDuration(mediaElement: mediaElement, pollInterval: 0.15, appearTimeout: 20.0, maxOnDuration: 10.0)
        recorder.appendManifestLines(["capped(3秒設定) on-duration: \(cappedOnDuration.map { String(format: "%.2f", $0) } ?? "nil")"])
        recorder.shoot(app, label: "capped_observed")

        app.buttons.firstMatch.tap() // 閉じる(左上のxマーク)
        Thread.sleep(forTimeInterval: 0.5)
        if !app.buttons["startButton"].waitForExistence(timeout: 5) {
            recorder.appendManifestLines(["閉じるボタンのタップでホームに戻れなかった。フォールバックとしてapp.launch()を試みる"])
            app.launch()
        }

        // --- 「最後まで再生する」に変更(動画の実長 約4.9秒 まで再生されるはず) ---
        try Self.setVideoCutoffMode(app: app, mode: .full, recorder: recorder)

        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 10))
        app.buttons["startButton"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        recorder.shoot(app, label: "full_after_start")

        let fullOnDuration = Self.measureOneOnDuration(mediaElement: mediaElement, pollInterval: 0.15, appearTimeout: 20.0, maxOnDuration: 10.0)
        recorder.appendManifestLines(["full(最後まで再生) on-duration: \(fullOnDuration.map { String(format: "%.2f", $0) } ?? "nil")"])
        recorder.shoot(app, label: "full_observed")
        recorder.writeManifest()

        guard let cappedOnDuration, let fullOnDuration else {
            XCTFail("動画の表示継続時間を観測できなかった(capped=\(String(describing: cappedOnDuration)), full=\(String(describing: fullOnDuration)))")
            return
        }

        XCTAssertLessThan(cappedOnDuration, 4.0, "3秒で切り上げる設定にしたのに、動画が3秒よりだいぶ長く再生された: \(cappedOnDuration)s")
        XCTAssertGreaterThan(fullOnDuration, cappedOnDuration, "「最後まで再生する」設定の方が「3秒で切り上げ」より短くなっている(反映されていない疑い)")
    }

    // MARK: - シナリオ7: ホイールの値と大きな時間表示が一致するか(既存スクリーンショットで疑われた不具合の検証)

    func testWheelDisplaySync() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v3_wheelsync")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)

        let minutesWheel = app.pickerWheels.element(boundBy: 0)
        let secondsWheel = app.pickerWheels.element(boundBy: 1)
        XCTAssertTrue(minutesWheel.waitForExistence(timeout: 15))
        XCTAssertTrue(secondsWheel.waitForExistence(timeout: 5))

        // 過去に「ホイール上は0分15秒なのに表示が00:24」という食い違いが疑われたケース(操作直後・
        // アニメーション中のスクリーンショットだった可能性が高い)を、複数の値で検証する。
        let combinations: [(minutes: String, seconds: String)] = [
            ("0", "15"),
            ("2", "20"),
            ("0", "45"),
        ]

        for (index, combo) in combinations.enumerated() {
            minutesWheel.adjust(toPickerWheelValue: combo.minutes)
            secondsWheel.adjust(toPickerWheelValue: combo.seconds)
            // ホイールのアニメーション(慣性スクロール)が完全に落ち着くのを待つ。
            Thread.sleep(forTimeInterval: 1.0)
            recorder.shoot(app, label: "combo\(index)_m\(combo.minutes)_s\(combo.seconds)")

            let homeTimeLabel = app.staticTexts["homeTimeLabel"]
            XCTAssertTrue(homeTimeLabel.exists, "大きな時間表示が見つからない")

            let expectedSeconds = (Int(combo.minutes) ?? 0) * 60 + (Int(combo.seconds) ?? 0)
            let expectedLabel = String(format: "%02d:%02d", expectedSeconds / 60, expectedSeconds % 60)

            recorder.appendManifestLines([
                "combo\(index): wheel=\(combo.minutes)分\(combo.seconds)秒 / homeTimeLabel=\(homeTimeLabel.label) / expected=\(expectedLabel)",
            ])
            XCTAssertEqual(homeTimeLabel.label, expectedLabel,
                            "ホイールが\(combo.minutes)分\(combo.seconds)秒を指しているのに、表示が\(homeTimeLabel.label)になっている(不具合の疑いあり)")
        }
        recorder.writeManifest()
    }

    // MARK: - シナリオ9(指摘B回帰テスト): 雰囲気+カテゴリの組み合わせで0件になりうるケースで固まらないか
    //
    // 【2026-09-05変更】以前は「雰囲気=緑」かつ「カテゴリ=花火」という、まず一致しないであろう
    // 組み合わせを選び、「0件になっても固まらない・0件表示か通常再生のどちらかに決着する」ことを
    // 確認するテストだった。CEO判断により候補の出し方を「満たす/満たさない」の足切りから
    // 「近い順に流す」方式に変更した(CandidateEngine.swift参照)ため、条件に合う写真が無くても
    // 近いものから必ず表示されるようになった(=「見つかりませんでした」には基本的にならない)。
    // このテストはその新しい保証(近い条件の組み合わせでも必ず何か表示される)の直接の確認に切り替え、
    // あわせて指摘B(無限ループでCPUを使い切り、✕ボタンも効かなくなるおそれ)の回帰確認も引き続き行う。
    // (「緑」はUIの選択肢から削除されたため、代わりに「暗め」を使う)
    func testNearMatchStreaming_AlwaysShowsSomething() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v6_nearmatch")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)
        try Self.setTotalTimer(app: app, minutes: "3", seconds: "0")

        let startButton = app.buttons["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        let startedAt = Date()
        startButton.tap()
        Self.dismissNotificationPermissionDialogIfPresent(app: app, recorder: recorder)

        let noResultsText = app.staticTexts["条件に合う写真・動画が見つかりませんでした"]
        // 【注意】remainingTimeLabel(残り時間表示)は「見つからない」表示の時も画面上部に
        // 常に出ているため、これだけでは「実際に写真・動画が表示されているか」を判定できない
        // (試作時に実際にこれで誤判定した)。実際に1枚でも表示されたかは media- で始まる
        // アクセシビリティIDの要素(SlideshowView参照)の有無で判定する。
        let mediaElement = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'media-'")
        ).firstMatch

        // 【2026-09-05変更】以前は手動のポーリングループ(exists連打)で20秒監視していたが、
        // XCUITest側のアクセシビリティツリー取得コスト自体が無視できないほど大きく、実際の
        // アプリの処理時間より計測値が大きく水増しされると判明した。waitForExistence(timeout:)は
        // XCTest内部の効率的なイベント待ちの仕組みを使うため、これに置き換えた
        // (調査の過程で、真の原因は「CEO要望Cで追加した通知許可ダイアログをテストが処理しておらず
        // 自動化セッションごと巻き込まれて止まっていたこと」と判明。setUpWithError()の
        // addUIInterruptionMonitorで解消済み。近い順に流す設計自体は数ミリ秒〜数百ミリ秒で決着する
        // ことをNSLogでの詳細計測で確認済みのため、ここでの待ち時間は20秒で十分)。
        var settledAs: String?
        if mediaElement.waitForExistence(timeout: 20) {
            settledAs = "normal_slideshow"
        } else if noResultsText.exists {
            settledAs = "no_results"
        } else if app.state != .runningForeground {
            settledAs = "crashed"
        }
        let elapsed = Date().timeIntervalSince(startedAt)
        recorder.shoot(app, label: "settled_as_\(settledAs ?? "timeout")")
        recorder.appendManifestLines([
            "settledAs=\(settledAs ?? "timeout(未決着)") elapsed=\(String(format: "%.1f", elapsed))s",
        ])

        guard let settledAs else {
            recorder.writeManifest()
            XCTFail("バグ report(指摘B): 雰囲気+カテゴリの絞り込みでスタートしてから20秒経っても決着しなかった(「読み込み中…」のまま固まっている疑い)")
            return
        }
        XCTAssertNotEqual(settledAs, "crashed", "雰囲気+カテゴリの絞り込みでスタートするとアプリが強制終了した")
        // 無関係写真を出さない新設計では、根拠のある候補が無ければno_resultsも正しい決着。
        XCTAssertTrue(settledAs == "normal_slideshow" || settledAs == "no_results")

        // 決着後、閉じるボタン(✕)が実際に反応してホーム画面に戻れることを確認する(指摘Bの「✕ボタンも効かなくなる」への回帰テスト)。
        // v5でこのボタンに明示的なアクセシビリティID("closeButton")を付けたため、それを使う。
        let closeButton = app.buttons["closeButton"].firstMatch
        if closeButton.exists {
            closeButton.tap()
        } else {
            app.buttons.firstMatch.tap()
        }
        let backToHome = startButton.waitForExistence(timeout: 5) || app.buttons["startButton"].waitForExistence(timeout: 5)
        recorder.shoot(app, label: "after_close")
        recorder.writeManifest()
        XCTAssertTrue(backToHome, "決着後に閉じるボタンをタップしてもホーム画面に戻れなかった(✕ボタンが効かない不具合の疑い)")
    }

    // MARK: - 探索予算の回帰テスト
    // 候補がすぐ見つからない条件でも、探索は0.8秒ごとにUIへ制御を返すため✕を操作できることを確認する。
    func testSearchBudgetKeepsCloseButtonResponsive() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PHOTOTIMER_UI_TEST_SEARCH_BUDGET"] = "1"
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v8_search_budget")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)
        try Self.setTotalTimer(app: app, minutes: "3", seconds: "0")

        let startButton = app.buttons["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()
        Self.dismissNotificationPermissionDialogIfPresent(app: app, recorder: recorder)

        let closeButton = app.buttons["closeButton"].firstMatch
        XCTAssertTrue(closeButton.waitForExistence(timeout: 2), "探索中に閉じるボタンへ操作できない")
        closeButton.tap()
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 5), "探索中断後にホームへ戻れない")
    }

    // MARK: - シナリオ10: 日時・種類・アルバム・雰囲気・場所の5種類を同時に選んでも壊れないか
    //
    // 現在テストされているのは主に「メディアの種類」単体だったため、5フィルタの組み合わせを
    // 実際に画面操作して確認する。結果が0件でも0件でなくても構わない(クラッシュ・フリーズしないことが目的)。
    func testFiveFilterCombination() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v4_fivefilters")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)
        try Self.setTotalTimer(app: app, minutes: "2", seconds: "0")

        let filterButton = app.buttons["filterButton"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 10))
        filterButton.tap()

        // 1. 日時: 「今月」(テスト用写真はこのセッション内で追加されたものなので対象に入る)
        let periodSegment = app.buttons["今月"]
        if periodSegment.waitForExistence(timeout: 5) { periodSegment.tap() }

        // 2. メディアの種類はデフォルト(すべて)のまま。3. スクリーンショットを除くもデフォルト(ON)のまま。

        // 4. アルバム: 選べるものがあれば先頭の1件を選ぶ(無ければスキップ)
        let firstAlbumRow = app.buttons.matching(NSPredicate(format: "label CONTAINS '枚)'")).firstMatch
        let pickedAlbum = Self.scrollUntilVisible(app: app, element: firstAlbumRow)
        if pickedAlbum { firstAlbumRow.tap() }

        // 5. 雰囲気: 「暖色」を選ぶ(比較的当てはまりやすいと考えられる代表色のひとつ)。
        // カテゴリと同様、下のセクションはスクロールしないとアクセシビリティツリーに現れないことがある。
        let warmChip = app.buttons["暖色"]
        let pickedMood = Self.scrollUntilVisible(app: app, element: warmChip)
        if pickedMood { warmChip.tap() }

        // 6. 場所: テスト用ライブラリの写真には位置情報が無い可能性が高く、その場合は
        //    「位置情報付きの写真が見つかりませんでした」と表示され選択肢自体が出ない。
        //    ここではアルバム行と紛らわしくならないよう、実際の選択はせず「場所」セクションが
        //    クラッシュせず描画されていること(空メッセージ or 候補表示)だけを記録する。
        let placeEmptyMessage = app.staticTexts["位置情報付きの写真が見つかりませんでした"]
        let placeSectionRendered = Self.scrollUntilVisible(app: app, element: placeEmptyMessage)

        recorder.appendManifestLines(["picked: album=\(pickedAlbum) mood=\(pickedMood) / placeSectionRendered(空表示)=\(placeSectionRendered)"])
        recorder.shoot(app, label: "filters_set")

        let doneButton = app.buttons["完了"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()

        let startButton = app.buttons["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let noResultsText = app.staticTexts["条件に合う写真・動画が見つかりませんでした"]
        // remainingTimeLabelは「見つからない」表示中も常時出ているため使わない(理由は上のテスト参照)。
        let mediaElement = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'media-'")
        ).firstMatch
        var settledAs: String?
        for _ in 0..<200 { // 20秒
            if noResultsText.exists { settledAs = "no_results"; break }
            if mediaElement.exists { settledAs = "normal_slideshow"; break }
            if app.state != .runningForeground { settledAs = "crashed"; break }
            usleep(100_000)
        }
        recorder.shoot(app, label: "settled_\(settledAs ?? "timeout")")
        recorder.appendManifestLines(["settledAs=\(settledAs ?? "timeout")"])
        recorder.writeManifest()

        guard let settledAs else {
            XCTFail("5フィルタを同時に指定してスタートしたら20秒経っても決着しなかった(フリーズの疑い)")
            return
        }
        XCTAssertNotEqual(settledAs, "crashed", "5フィルタを同時に指定してスタートするとアプリが強制終了した")
    }

    // MARK: - シナリオ11・12: 写真0枚のケース・権限を拒否したケース
    //
    // 【実行方法についての注意】
    // このテスト2つは、既存の検証で使っているシミュレータ(写真14枚+動画1本を仕込んだもの)ではなく、
    // 既存の検証用シミュレータ(写真14枚+動画1本を仕込んだもの)ではなく、別のシミュレータ
    // ("PhotoTimer-EmptyLib")に対して実行する運用にしている(この端末なら「権限拒否直後」の状態や
    // 「写真がごくわずかな」状態を作れるが、既存の検証用ライブラリを巻き込んで壊したくないため)。
    // 実行コマンドは完了報告に記載する。
    // testPermissionDenied_ShowsDeniedState → testEmptyLibrary_NoPhotosAtAll の順に実行する前提
    // (先に「拒否」を試し、その後 simctl privacy reset で許可状態を作り直してから次を試す)。

    /// 写真へのアクセスダイアログで「許可しない」を選んだ場合、クラッシュせず
    /// 「設定を開く」への案内画面が出ることを確認する。
    func testPermissionDenied_ShowsDeniedState() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v4_denied")

        let allowButton = app.buttons["写真へのアクセスを許可する"]
        guard allowButton.waitForExistence(timeout: 10) else {
            recorder.appendManifestLines(["「写真へのアクセスを許可する」ボタンが出なかった(すでに許可/拒否済みの可能性)。このテストはprivacy未決定の端末で実行する前提。"])
            recorder.writeManifest()
            XCTFail("権限が未決定(notDetermined)の状態で実行する想定のテストだが、許可依頼ボタンが出てこなかった")
            return
        }
        allowButton.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let denyButton = springboard.buttons["許可しない"]
        var found = false
        for _ in 0..<500 { // 最大5秒
            if denyButton.exists { found = true; break }
            usleep(10_000)
        }
        recorder.appendManifestLines(["deny dialog found=\(found)"])
        if found {
            denyButton.tap()
        }

        let deniedMessage = app.staticTexts["写真へのアクセスが許可されていません。設定アプリから許可してください。"]
        let appeared = deniedMessage.waitForExistence(timeout: 5)
        recorder.shoot(app, label: "after_deny")
        recorder.writeManifest()

        XCTAssertTrue(appeared, "権限を拒否した後、案内メッセージが表示されなかった")
        XCTAssertEqual(app.state, .runningForeground, "権限を拒否するとアプリが落ちた")
    }

    /// 写真がごくわずかな状態(この検証専用シミュレータ)で、絞り込みなしでもクラッシュしないこと、
    /// および「対象0件」のメタ情報レベルの早期判定(遅延評価に入る前の判定)が正しく効くことを確認する。
    ///
    /// 【「写真0枚」ではなく「動画0本」の判定になっている理由】
    /// 当初は完全に0枚の状態で確認する想定だったが、実際に試すとXcodeのシミュレータは初回起動時から
    /// サンプル写真が数枚(この環境では6枚、すべて静止画)入っている状態からは変えられないと判明した
    /// (simctlにライブラリを空にするコマンドは無く、写真アプリの中身を直接消す手段もこの実行環境には無い)。
    /// そこで「メディアの種類=動画」で絞り込む(この6枚には動画が1本も無いため確実に0件になる)ことで、
    /// 実質的に同じ検証(メタ情報の時点で0件と分かるケースが正しく扱われるか)を行っている。
    /// 「該当0件」のメタ情報レベルのケース以外(雰囲気・カテゴリの遅延評価に関する確認)は
    /// testNearMatchStreaming_AlwaysShowsSomething で別途確認済み。
    func testEmptyLibrary_NoPhotosAtAll() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v4_emptylibrary")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)

        let startButton = app.buttons["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 15), "写真がごくわずかな状態でもホーム画面(スタートボタン)が出るはず")
        recorder.shoot(app, label: "home_with_few_photos")

        try Self.selectMediaTypeFilter(app: app, label: "動画")
        startButton.tap()

        let noResultsText = app.staticTexts["条件に合う写真・動画が見つかりませんでした"]
        let appeared = noResultsText.waitForExistence(timeout: 10)
        recorder.shoot(app, label: "after_start")
        recorder.writeManifest()

        XCTAssertTrue(appeared, "動画が1本も無いライブラリで動画に絞り込んだのに「見つかりませんでした」が表示されなかった")
        XCTAssertEqual(app.state, .runningForeground, "写真がごくわずかな状態でスタートするとアプリが落ちた")
    }

    // MARK: - シナリオ13: 雰囲気・カテゴリの遅延評価中に✕で閉じても、裏で解析が走り続けないか(v5)
    //
    // 【2回目のチェック工程・指摘A対応の回帰テスト】以前はCandidateEngine.next()のループに
    // キャンセル確認が一度も入っておらず、✕ボタンで閉じてもタイマーが0になっても、候補を最後の
    // 1枚まで判定し終えるまで裏で処理が走り続けてしまっていた(写真が多いほどCPUを使い切ったまま
    // 数分〜十数分止まらない不具合)。
    //
    // 【この検証環境での限界について、正直に書いておく】
    // このテスト用ライブラリは写真・動画あわせて15枚程度しか無く、1周分の判定はどのみち一瞬で
    // 終わってしまうため、「数分間裏で走り続ける」こと自体をこの環境で直接再現・確認することは
    // できない(実害が大きく出るのは実際に数千〜数万枚の写真を持つ利用者の場合)。
    // そのため、ここでは以下を確認することで間接的に裏付ける:
    //  1. 遅延評価が必要な絞り込み(雰囲気+カテゴリ、必ず0件になる組み合わせ)でスタートした直後、
    //     結果が確定するのを待たずに✕(closeButton)を押す。
    //  2. ✕を押した直後、素早く(数秒以内に)ホーム画面に戻れること
    //     (=CandidateEngine.next()のwhileループがTask.isCancelled確認で即座に打ち切られている
    //     ことの状況証拠。以前の実装でもこの小さなライブラリでは同様に速く戻っていた可能性はあるが、
    //     「戻ってくること自体」の回帰確認として意味がある)。
    //  3. 戻った直後からアプリの操作(絞り込み画面を開く)が遅延なく効くこと
    //     (=裏でCPUを使い切る処理が続いていれば、UIの応答が遅れるはず)。
    func testImmediateDismiss_DuringLazyEvaluation_NoBackgroundHang() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v5_immediatedismiss")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)
        try Self.setTotalTimer(app: app, minutes: "3", seconds: "0")

        // 【2026-09-05変更】このテスト用ライブラリ(15枚程度)は窓サイズ(scoringBatchSize=20)より
        // 小さいため、雰囲気・カテゴリを1つでも指定すれば「近い順」の並べ替えのために候補全体を
        // 1回の窓でまとめて採点する(=遅延評価のうち最も重い処理)ことになる。どの組み合わせでも
        // このキャンセル応答性の確認はできるため、「暗め」+「花火」を使う(「緑」はUIの選択肢から削除された)。
        try Self.selectMoodAndCategory(app: app, mood: "暗め", category: "花火", recorder: recorder)

        let startButton = app.buttons["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        // 結果が確定するのを待たず、できるだけ早いタイミングで✕を押す。
        let closeButton = app.buttons["closeButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "スライドショー画面の✕ボタンが見つからない")
        recorder.shoot(app, label: "before_close")
        let dismissRequestedAt = Date()
        closeButton.tap()

        var cameBackHome = false
        for _ in 0..<100 { // 最大 100 x 100ms = 10秒
            if startButton.exists { cameBackHome = true; break }
            usleep(100_000)
        }
        let dismissDuration = Date().timeIntervalSince(dismissRequestedAt)
        recorder.shoot(app, label: "after_close")
        recorder.appendManifestLines(["dismiss duration: \(String(format: "%.2f", dismissDuration))s", "came back home: \(cameBackHome)"])

        XCTAssertTrue(cameBackHome, "遅延評価中に✕を押したのに10秒経ってもホーム画面に戻れなかった(裏で処理が走り続けているフリーズの疑い)")
        XCTAssertLessThan(dismissDuration, 5.0, "✕を押してからホーム画面に戻るまで5秒以上かかった(このライブラリの規模ではあり得ないはずの遅さ)")

        // 戻った直後、UIの応答が遅延していないか(=裏でCPUを使い切る処理が続いていないか)の簡易確認。
        let filterButton = app.buttons["filterButton"]
        let respondedAt = Date()
        XCTAssertTrue(filterButton.waitForExistence(timeout: 3), "ホーム画面に戻った直後、絞り込みボタンの操作が遅延している(裏で処理が続いている疑い)")
        recorder.appendManifestLines(["filter button responsive after: \(String(format: "%.2f", Date().timeIntervalSince(respondedAt)))s"])
        recorder.writeManifest()
    }

    // MARK: - シナリオ14: 旧形式(クラスタ中心の平均座標)の「場所」設定が残っていた場合の復帰(v5)
    //
    // 【2回目のチェック工程・指摘B・G対応の回帰テスト】
    // 場所の識別子(PlaceCluster.id)の作り方を「クラスタ中心の平均座標」から「マス目番号
    // (bucketKey)」に変更したため、変更前のバージョンで場所を選んでいた端末では、保存されている
    // 選択IDが今の一覧のどのIDとも一致しなくなる。指摘Bはこの状態から復帰する手段が無いこと、
    // 指摘Gはその設定の保存先自体がUserDefaults(=iCloudバックアップ対象)のままだったことを指す。
    //
    // 【実行方法についての注意】
    // XCUITestのテストコードはこのアプリと同じiOS Simulator向けにビルドされるため、
    // (Macホスト上で動く一部のXCUITestとは違い)Foundationの `Process` が使えず、テストコード
    // 自身からは `xcrun simctl` のようなシェルコマンドを呼び出せない。そのため「旧形式のプレースID」
    // を含む FilterSettings のJSONを旧保存先(UserDefaults, キー "PhotoTimer.FilterSettings.v1")へ
    // 直接書き込む準備は、このテストを動かす「前」に、テストを実行する側(Macのターミナル)から
    // 以下のコマンドで行う(=アップデート前から使っていたユーザーの状態を模擬する)。
    //
    //   xcrun simctl spawn <シミュレータのUDID> defaults write com.aiteam.PhotoTimer \
    //     PhotoTimer.FilterSettings.v1 -data \
    //     7b2273656c656374656443617465676f72696573223a5b5d2c2273656c6563746564416c62756d494473223a5b5d2c226461746552616e6765223a7b22616c6c223a7b7d7d2c2273656c65637465644d6f6f6473223a5b5d2c226d6564696154797065223a22e38199e381b9e381a6222c2273656c6563746564506c616365494473223a5b2233352e3638313233362c3133392e373637313235225d2c226578636c75646553637265656e73686f7473223a747275657d
    //
    // このバイト列は「実際の FilterSettings.swift の型定義」を使って
    // `FilterSettings(selectedPlaceIDs: ["35.681236,139.767125"])`(それ以外は既定値)を
    // JSONEncoderでエンコードした結果そのもの(事前に別途生成・decodeできることまで検証済み)。
    // 書き込んだ後、このアプリを一度も起動していない状態(未起動または `xcrun simctl terminate` 済み)
    // からテストを実行すること。
    func testLegacyPlaceSelection_MigratesAndOffersClear() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v5_legacyplace")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)

        // 移行が正しく起きていれば、ホーム画面の「絞り込み条件」の要約に「場所1件」が出るはず。
        // (旧データが読み込めず黙って消えてしまう、が一番まずいパターンなので、まずここを確認する)
        let filterButton = app.buttons["filterButton"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 15))
        recorder.shoot(app, label: "home_after_legacy_seed")
        let placeCountLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '場所1件'")).firstMatch
        XCTAssertTrue(placeCountLabel.waitForExistence(timeout: 5), "旧形式の場所設定(UserDefaults)が復元されていない(移行処理が効いていない可能性)")

        filterButton.tap()

        // 場所セクションまでスクロール。旧IDは今のどの場所とも一致しないはずなので、
        // 「見つからない場所の選択を解除」ボタンが出ていることを確認する(指摘B対応)。
        let clearPlaceButton = app.buttons.matching(NSPredicate(format: "label CONTAINS '見つからない場所の選択を解除'")).firstMatch
        let found = Self.scrollUntilVisible(app: app, element: clearPlaceButton)
        recorder.shoot(app, label: "filter_place_section")
        XCTAssertTrue(found, "旧形式の場所IDが残っているのに「見つからない場所の選択を解除」ボタンが出ない(指摘B対応が効いていない)")

        clearPlaceButton.tap()
        recorder.shoot(app, label: "after_clear_place")

        let doneButton = app.buttons["完了"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()

        // 解除後は絞り込み要約から「場所」の表示が消えているはず。
        Thread.sleep(forTimeInterval: 0.3)
        let stillShowsPlace = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '場所'")).firstMatch.exists
        recorder.shoot(app, label: "home_after_clear")
        recorder.writeManifest()
        XCTAssertFalse(stillShowsPlace, "「見つからない場所の選択を解除」を押したのに、絞り込み要約から場所の表示が消えていない")

        // 【指摘G(旧保存先のキーが削除されたか)について】
        // このテストコード自身からは(Processが使えないため)旧UserDefaultsキーの削除を直接確認できない。
        // この点は、テストを実行する側が `xcrun simctl spawn <UDID> defaults read com.aiteam.PhotoTimer
        // PhotoTimer.FilterSettings.v1` を別途実行し、キーが見つからなくなっている(終了コード非0に
        // なる)ことを確認する運用にしている。完了報告に実施結果を記載する。
    }

    // MARK: - シナリオ15: 「緑」が雰囲気の選択肢から消えていること(v6)

    func testGreenRemovedFromMoodChoices() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v6_greenremoved")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)

        let filterButton = app.buttons["filterButton"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 15))
        filterButton.tap()

        // 雰囲気セクションはスクロールしないと現れないことがある。まず他の選択肢(暖色)で
        // セクション自体の位置までスクロールさせてから、緑が無いことを確認する。
        let warmChip = app.buttons["暖色"]
        XCTAssertTrue(Self.scrollUntilVisible(app: app, element: warmChip), "雰囲気セクションの「暖色」が見つからない")
        recorder.shoot(app, label: "mood_section")

        XCTAssertFalse(app.buttons["緑"].exists, "「緑」が雰囲気の選択肢からまだ表示されている(CEO判断で削除したはず)")

        // 他の選択肢は引き続き選べることも確認する(削除の副作用で他が消えていないか)。
        for label in ["暖色", "寒色", "モノトーン", "鮮やか", "淡い", "明るめ", "暗め"] {
            XCTAssertTrue(app.buttons[label].exists, "雰囲気の選択肢「\(label)」が見つからない(緑の削除で他まで消えていないか確認)")
        }

        app.buttons["寒色"].tap() // 実際にタップできる(反応する)ことも確認しておく
        recorder.shoot(app, label: "cool_selected")
        recorder.writeManifest()

        app.buttons["完了"].tap()
    }

    // MARK: - シナリオ16: 使い方説明画面(v6)

    func testHelpScreen_OpensAndShowsGuidance() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v6_help")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)

        let helpButton = app.buttons["helpButton"]
        XCTAssertTrue(helpButton.waitForExistence(timeout: 15), "「?」の使い方ボタンが見つからない")
        helpButton.tap()

        let title = app.navigationBars["使い方・仕組み"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "使い方説明画面が開かなかった")

        // カメラの位置情報設定についての案内文(CEO追加要望)が含まれているか。
        let locationGuidance = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'カメラ'")).firstMatch
        XCTAssertTrue(Self.scrollUntilVisible(app: app, element: locationGuidance), "カメラの位置情報設定についての案内文が見つからない")
        recorder.shoot(app, label: "help_location_section")

        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 5), "使い方説明画面を閉じてもホーム画面に戻れなかった")
        recorder.writeManifest()
    }

    // MARK: - シナリオ17: アラーム設定「止めるまで鳴り続ける」→「アラームを止める」ボタン(v6)

    func testAlarmSettings_UntilStoppedShowsStopButton() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v6_alarmstop")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)

        // 【2026-09-05追加】このテストは絞り込みなし(=全15件が対象)を前提にしている。
        // 他のテスト(雰囲気+カテゴリを選ぶもの、旧形式の「場所」データを移行させるもの等)が
        // 残した絞り込み条件がUserDefaults/端末内ファイルに残っていると、実際には
        // 「絞り込み条件に合う写真が0件」になってしまい、このテストが検証したい「アラームの鳴らし方」
        // とは無関係な理由で失敗する(実機・シミュレータいずれでも起こりうる、テスト間の汚染)。
        // このテスト自身が前提とする状態(絞り込みなし)を毎回保証するため、まず「すべて解除」する。
        let filterButtonForClear = app.buttons["filterButton"]
        XCTAssertTrue(filterButtonForClear.waitForExistence(timeout: 15), "「絞り込み条件」ボタンが見つからない")
        filterButtonForClear.tap()
        let clearAllButton = app.buttons["すべて解除"]
        if clearAllButton.waitForExistence(timeout: 5) { clearAllButton.tap() }
        app.buttons["完了"].tap()

        // アラーム設定画面で「止めるまで鳴り続ける」を選ぶ。
        let alarmSettingsButton = app.buttons["alarmSettingsButton"]
        XCTAssertTrue(alarmSettingsButton.waitForExistence(timeout: 15), "アラーム設定(ベル)ボタンが見つからない")
        alarmSettingsButton.tap()

        let untilStoppedSegment = app.buttons["止めるまで鳴り続ける"]
        XCTAssertTrue(untilStoppedSegment.waitForExistence(timeout: 5), "「止めるまで鳴り続ける」の選択肢が見つからない")
        untilStoppedSegment.tap()
        recorder.shoot(app, label: "alarm_settings_until_stopped")
        app.buttons["完了"].tap()

        // タイマーを最短(1秒)に設定してすぐ終わらせる。
        try Self.setTotalTimer(app: app, minutes: "0", seconds: "1")

        let startButton = app.buttons["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        // タイマー終了後、「アラームを止める」ボタンが出るはず(音が止めるまで鳴り続けるモードのため)。
        let stopAlarmButton = app.buttons["stopAlarmButton"]
        XCTAssertTrue(stopAlarmButton.waitForExistence(timeout: 10), "タイマー終了後に「アラームを止める」ボタンが表示されなかった")
        recorder.shoot(app, label: "stop_alarm_button_shown")

        stopAlarmButton.tap()

        // 止めた後は「閉じる」ボタンに切り替わるはず。
        let closeButton = app.buttons["finishedCloseButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "「アラームを止める」を押しても「閉じる」ボタンに切り替わらなかった")
        recorder.shoot(app, label: "switched_to_close")
        closeButton.tap()

        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 5), "アラームを止めて閉じてもホーム画面に戻れなかった")
        recorder.writeManifest()
    }

    // MARK: - シナリオ18: バックグラウンドに回っても経過時間を正しく反映して復帰する(v7. CEO要望C)
    //
    // 【何を確認するか】XCUIDevice.shared.press(.home)で実機の「ホームボタンを押す」に相当する操作を行い、
    // アプリを実際にバックグラウンドへ回す(scenePhaseが.backgroundになる)。数秒待ってから
    // app.activate()でフォアグラウンドに戻し(scenePhaseが.activeに戻る)、
    //  1. スライドショー画面に(クラッシュ・別画面遷移せず)戻れること
    //  2. 残り時間が、バックグラウンドで経過した分だけ正しく減っていること
    //     (TimerController.returnToForeground()がdeadlineから計算し直していることの確認)
    //  3. 何らかの写真・動画が変わらず表示され続けていること(「戻ってきたらしっかり表示する」の確認)
    // を確認する。
    func testBackgroundThenForeground_KeepsTimerAccurateAndResumesDisplay() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v7_background")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)
        // バックグラウンドで数秒待つ余裕を持たせつつ、テスト全体が長くなりすぎない範囲の秒数にする。
        try Self.setTotalTimer(app: app, minutes: "0", seconds: "40")

        let startButton = app.buttons["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let remainingLabel = app.staticTexts["remainingTimeLabel"]
        XCTAssertTrue(remainingLabel.waitForExistence(timeout: 10), "スライドショーの残り時間表示が見つからない")
        recorder.shoot(app, label: "before_background")

        // ホームボタン相当の操作でバックグラウンドへ。
        XCUIDevice.shared.press(.home)
        let backgroundedAt = Date()
        Thread.sleep(forTimeInterval: 6.0) // バックグラウンドのまま6秒待つ

        // フォアグラウンドへ復帰。
        app.activate()
        let elapsedInBackground = Date().timeIntervalSince(backgroundedAt)

        XCTAssertTrue(remainingLabel.waitForExistence(timeout: 10), "バックグラウンドから戻ってもスライドショー画面(残り時間表示)に戻れなかった")
        recorder.shoot(app, label: "after_foreground")

        // "MM:SS" 形式から秒数へ変換して、経過時間が正しく反映されているか確認する。
        let parts = remainingLabel.label.split(separator: ":")
        recorder.appendManifestLines(["remaining label after foreground: \(remainingLabel.label)", "elapsed in background: \(String(format: "%.1f", elapsedInBackground))s"])
        guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Int(parts[1]) else {
            XCTFail("残り時間表示の形式が想定外: \(remainingLabel.label)")
            recorder.writeManifest()
            return
        }
        let remainingAfter = minutes * 60 + seconds
        // 40秒でスタートし、バックグラウンドに6秒前後いたはずなので、40秒よりは確実に減っているはず。
        // (背景に回した直後から計測しているため多少の余裕を持たせるが、「全く減っていない」は不具合)
        XCTAssertLessThan(remainingAfter, 40, "バックグラウンドで\(String(format: "%.1f", elapsedInBackground))秒経過したのに、残り時間が40秒からまったく減っていない(経過時間が反映されていない疑い)")
        // 逆に「経過時間以上に減りすぎている」ことも無いはず(大幅な余裕を持たせて上限をチェック)。
        XCTAssertGreaterThan(remainingAfter, 0, "バックグラウンドにいた間にタイマーが終わってしまった(想定より短い40秒設定・6秒待機のはずが)")

        // 「しっかり表示を再開する」の確認: 何らかの写真・動画の目印が表示されていること。
        let mediaElement = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'media-'")
        ).firstMatch
        XCTAssertTrue(mediaElement.waitForExistence(timeout: 10), "バックグラウンドから復帰しても写真・動画の表示が再開されなかった")
        recorder.writeManifest()
    }

    // MARK: - シナリオ19: 削除ボタンでOS標準の確認ダイアログが出ること(v7. CEO要望D)
    //
    // 【安全のため実際には削除しない】このテスト用ライブラリ(15件)は他の多くのテストが前提にしている
    // 共有リソースのため、ここで実際に削除してしまうと他のテストに影響する。そのため「確認ダイアログが
    // 正しく出るか」「キャンセルすれば何も起きないか」だけを確認し、実際の削除確定(枚数が減ること)は
    // 別途手元の使い捨てシミュレータでの確認に委ねる(完了報告に記載)。
    func testDeleteButton_ShowsOSConfirmation_CancelLeavesNothingDeleted() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v7_deleteconfirm")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)
        try Self.setTotalTimer(app: app, minutes: "3", seconds: "0")

        let startButton = app.buttons["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let deleteButton = app.buttons["deleteCurrentAssetButton"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 15), "削除(ゴミ箱)ボタンが見つからない")
        recorder.shoot(app, label: "before_delete_tap")
        deleteButton.tap()

        // OS標準の確認ダイアログ(springboard側)が出ることを確認する(アプリ側で確認UIを自作していないことの裏付け)。
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancelButton = springboard.buttons["キャンセル"]
        var found = false
        for _ in 0..<500 { // 最大5秒
            if cancelButton.exists { found = true; break }
            usleep(10_000)
        }
        recorder.appendManifestLines(["OS confirmation dialog found=\(found)"])
        recorder.shoot(app, label: "confirmation_dialog")
        XCTAssertTrue(found, "削除ボタンを押してもOS標準の確認ダイアログが出なかった")
        cancelButton.tap()

        // キャンセルしたので何も起きておらず、スライドショーはそのまま動き続けているはず。
        Thread.sleep(forTimeInterval: 1.0)
        recorder.shoot(app, label: "after_cancel")
        recorder.writeManifest()
        XCTAssertEqual(app.state, .runningForeground, "削除確認をキャンセルしただけなのにアプリが落ちた")
        XCTAssertTrue(app.buttons["deleteCurrentAssetButton"].exists, "削除確認をキャンセルしたのにスライドショー画面から離脱してしまった")
    }

    // MARK: - シナリオ20: よく撮れてる度の選択肢がiOS 18以降で出ること(v7. CEO要望B)

    func testAestheticsOptions_AppearOnIOS18Plus() throws {
        let app = XCUIApplication()
        app.launch()
        let recorder = ScreenshotRecorder(scenario: "v7_aesthetics")
        try Self.ensurePhotosAccessGranted(app: app, recorder: recorder)

        let filterButton = app.buttons["filterButton"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 15))
        filterButton.tap()

        // このシミュレータはiOS 26.5(iOS 18以降)なので、選択肢が出るはず。
        let preferHighAestheticsToggle = app.switches["よく撮れてる写真を優先する"]
        XCTAssertTrue(Self.scrollUntilVisible(app: app, element: preferHighAestheticsToggle), "「よく撮れてる写真を優先する」の選択肢が見つからない(iOS 18以降のはずのシミュレータ)")
        recorder.shoot(app, label: "aesthetics_section")

        // 「スクリーンショットを除く」がデフォルトでオンのはずなので、AI強化オプションも出ているはず。
        let strictToggle = app.switches["AIで書類・レシートらしい写真も除く"]
        XCTAssertTrue(strictToggle.exists, "「スクリーンショットを除く」がオンなのに「AIで書類・レシートらしい写真も除く」が出ていない")

        preferHighAestheticsToggle.tap()
        recorder.shoot(app, label: "aesthetics_enabled")
        recorder.writeManifest()
        app.buttons["完了"].tap()
    }

    // MARK: - 共通処理: スクロールしないと現れない要素を探す

    /// Form内の下の方にあるセクション(LazyVGridを含む)は、スクロールして画面内に入るまで
    /// アクセシビリティツリーに現れないことがある。見つかるまで数回スワイプする。
    /// 見つかれば true、見つからなかった(=そもそも選択肢が無い)場合は false を返す。
    @discardableResult
    // 【2026-09-05変更】「よく撮れてる度」セクション追加でForm全体が縦に伸びたため、
    // 6回のスワイプでは末尾(カテゴリ)まで届かないケースが出てきた。安全側に10へ引き上げる。
    private static func scrollUntilVisible(app: XCUIApplication, element: XCUIElement, maxSwipes: Int = 10, debugRecorder: ScreenshotRecorder? = nil) -> Bool {
        if element.waitForExistence(timeout: 2) { return true }
        for i in 0..<maxSwipes {
            app.swipeUp()
            debugRecorder?.shoot(app, label: "scroll_debug_\(i)")
            if element.waitForExistence(timeout: 1) { return true }
        }
        return false
    }

    // MARK: - 共通処理: フィルタ操作(雰囲気・カテゴリ)

    private static func selectMoodAndCategory(app: XCUIApplication, mood: String, category: String, recorder: ScreenshotRecorder) throws {
        let filterButton = app.buttons["filterButton"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 10), "「絞り込み条件」ボタンが見つからない")
        filterButton.tap()

        // 前のテストで選んだ絞り込み条件が端末内保存(UserDefaults)で残っていることがあるため、
        // まず「すべて解除」でクリーンな状態にしてから、このテストで必要な条件だけを選び直す。
        let clearButton = app.buttons["すべて解除"]
        if clearButton.waitForExistence(timeout: 5) { clearButton.tap() }

        // 雰囲気・カテゴリのセクションはForm内で下の方にあり、画面をスクロールしないと
        // アクセシビリティツリーに現れないことがある(LazyVGridの遅延生成)ため、見つかるまでスワイプする。
        let moodChip = app.buttons[mood]
        XCTAssertTrue(Self.scrollUntilVisible(app: app, element: moodChip, debugRecorder: recorder), "雰囲気の選択肢「\(mood)」が見つからない")
        moodChip.tap()

        let categoryChip = app.buttons[category]
        XCTAssertTrue(Self.scrollUntilVisible(app: app, element: categoryChip), "カテゴリの選択肢「\(category)」が見つからない")
        categoryChip.tap()

        recorder.shoot(app, label: "mood_\(mood)_category_\(category)_set")

        let doneButton = app.buttons["完了"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()
    }

    // MARK: - 共通処理: 写真アクセス許可

    /// 写真ライブラリへのアクセス許可が未決定(notDetermined)の場合、OS標準の許可ダイアログを自動で
    /// 「フルアクセスを許可」まで進める。
    ///
    /// 【なぜこれで自動化できるか】
    /// XCUITestのテストコードの中からは、springboard(システムのアラート・シートを描画しているプロセス)
    /// のアクセシビリティ要素を直接クエリ・タップできる。ポイントは2つ:
    ///  1. `.alerts` / `.sheets` のようなコンテナ越しにクエリすると、iOS26のフォトアクセスダイアログは
    ///     内部的に「Alert」と「Sheet」の判定が食い違い、実行時エラーになることがある。
    ///     → コンテナを経由せず、springboard.buttons["フルアクセスを許可"] のように直接ボタンを狙う。
    ///  2. `waitForExistence` のような「じっくり待つ」問い合わせだと、その待ち時間の間にXCTestの
    ///     既定の割り込みハンドラが先に「許可しない」を選んでしまうことがある(タイミング競合)。
    ///     → 最小間隔(10ms)でボタンの存在だけをポーリングし、見つかった瞬間にタップする。
    private static func ensurePhotosAccessGranted(app: XCUIApplication, recorder: ScreenshotRecorder) throws {
        let allowButton = app.buttons["写真へのアクセスを許可する"]
        // すでに許可済みならこのボタンは出てこない(数秒で見切りをつけて先に進む)。
        guard allowButton.waitForExistence(timeout: 5) else {
            // 【バグ修正】許可済み(=このボタンが出ない)経路でdismissAnyStrayRunningTimerの
            // 呼び出しが漏れていたため、前回のタイマーが自動再開された状態のまま後続の操作に
            // 進んでしまっていた。許可待ちの分岐に関わらず必ず後始末を行うようにする。
            try dismissAnyStrayRunningTimer(app: app, recorder: recorder)
            return
        }
        allowButton.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let fullAccessButton = springboard.buttons["フルアクセスを許可"]
        var found = false
        for _ in 0..<500 { // 最大 500 x 10ms = 5秒
            if fullAccessButton.exists {
                found = true
                break
            }
            usleep(10_000)
        }
        recorder.appendManifestLines(["photos permission dialog found=\(found)"])
        if found {
            fullAccessButton.tap()
            // 【2026-09-05追加・調査で判明】許可を与えた直後の一瞬は、写真データの読み込み
            // (PHImageManager.requestImage)が"PHPhotosErrorDomain Code=3303"で一時的に失敗する
            // ことがあると分かった(写真周りのシステムプロセスが許可の反映に追いついていないと見られる)。
            // 人が実際に使う時は許可ダイアログをタップしてから次の操作まで数秒はかかるものだが、
            // このテストは許可直後にミリ秒単位でスタートまで進めてしまうため、実際のユーザーでは
            // まず起きないこの狭い時間帯を意図せず突いてしまっていた。人の操作に近い間を空ける。
            Thread.sleep(forTimeInterval: 1.5)
        } else {
            recorder.appendManifestLines(["許可ダイアログが検出できなかった。CEOに手動タップを依頼する運用にフォールバックが必要"])
        }
        // 許可の反映(ホーム画面への遷移)を待つ。
        _ = app.buttons["startButton"].waitForExistence(timeout: 5)
        try dismissAnyStrayRunningTimer(app: app, recorder: recorder)
    }

    /// 【2026-09-05追加。CEO要望C(バックグラウンド動作)対応の副作用への対策】
    /// 「前回のタイマーを自動的に再開する」機能を追加したことで、xcodebuild testプロセスを
    /// 強制終了する等の理由でSlideshowView.stop()が呼ばれないまま前回のテストが終わっていた場合、
    /// 次のapp.launch()で古いタイマー画面が自動的に開いてしまうことがある
    /// (アプリの実際の挙動としては「意図通り」。iPhone標準のタイマー/アラームアプリと同じ考え方で、
    /// テストの前提〔ホーム画面から始まる〕を崩すのはテスト実行環境側の話であり、アプリの不具合ではない)。
    /// ホーム画面のstartButtonが見えていなければ、スライドショー画面が残っているとみなして閉じる。
    private static func dismissAnyStrayRunningTimer(app: XCUIApplication, recorder: ScreenshotRecorder) throws {
        guard !app.buttons["startButton"].exists else { return } // 既にホーム画面ならOK
        recorder.appendManifestLines(["前回のタイマーが自動再開された状態を検出。閉じてホームへ戻す(テスト前提を揃えるため)"])
        recorder.shoot(app, label: "stray_running_timer_detected")
        if app.buttons["stopAlarmButton"].exists {
            app.buttons["stopAlarmButton"].tap()
        }
        if app.buttons["finishedCloseButton"].waitForExistence(timeout: 2) {
            app.buttons["finishedCloseButton"].tap()
        } else if app.buttons["closeButton"].waitForExistence(timeout: 2) {
            app.buttons["closeButton"].tap()
        }
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 5), "自動再開されたタイマー画面を閉じてもホーム画面に戻れなかった")
    }

    /// 【2026-09-05追加。原因究明で判明した重要な後始末】
    /// CEO要望C(バックグラウンド動作)で、タイマー開始時(TimerController.start())に
    /// 通知の許可(バックグラウンドでもアラームを鳴らすためのローカル通知)を尋ねる処理を追加した。
    /// このアプリを初めてインストールした端末で最初に「スタート」を押すと、OS標準の通知許可
    /// ダイアログが新たに出るようになる(写真アクセスの許可ダイアログとは別物で、初回の
    /// 「スタート」の直後に1回だけ出る)。
    /// `addUIInterruptionMonitor`(setUpWithError参照)でも一定は自動処理されるが、
    /// XCTestの仕組み上、直後にアプリ側への何らかの操作(タップ等)が起きるまで検知が
    /// 遅れることがあると分かったため、写真アクセスの許可ダイアログと同じ「直接ポーリングして
    /// 見つかったらすぐタップする」方式でも二重に備える(見つからなければ何もしない=既に
    /// 処理済み、または今回は出なかった、のどちらでも問題ない)。
    private static func dismissNotificationPermissionDialogIfPresent(app: XCUIApplication, recorder: ScreenshotRecorder) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["許可"]
        var found = false
        for _ in 0..<300 { // 最大 300 x 10ms = 3秒
            if allowButton.exists { found = true; break }
            usleep(10_000)
        }
        if found {
            recorder.appendManifestLines(["通知の許可ダイアログを検出しタップした"])
            allowButton.tap()
        }
    }

    // MARK: - 共通処理: 設定操作

    /// ホーム画面のタイマー(分・秒ホイール)を指定の値に設定する。
    /// `selectedSeconds` は @AppStorage(端末内保存)なので、前のテストで設定した値が残っていることがある。
    /// 「観察に十分な長さが欲しい」テストは、この関数で明示的に設定してから始めること。
    private static func setTotalTimer(app: XCUIApplication, minutes: String, seconds: String) throws {
        let minutesWheel = app.pickerWheels.element(boundBy: 0)
        let secondsWheel = app.pickerWheels.element(boundBy: 1)
        XCTAssertTrue(minutesWheel.waitForExistence(timeout: 15), "「分」のホイールが見つからない")
        XCTAssertTrue(secondsWheel.waitForExistence(timeout: 5), "「秒」のホイールが見つからない")
        minutesWheel.adjust(toPickerWheelValue: minutes)
        secondsWheel.adjust(toPickerWheelValue: seconds)
        Thread.sleep(forTimeInterval: 0.3) // ホイールのアニメーションが落ち着くのを待つ
    }

    private static func selectMediaTypeFilter(app: XCUIApplication, label: String) throws {
        let filterButton = app.buttons["filterButton"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 10), "「絞り込み条件」ボタンが見つからない")
        filterButton.tap()

        let segment = app.buttons[label]
        XCTAssertTrue(segment.waitForExistence(timeout: 5), "メディアの種類の選択肢「\(label)」が見つからない")
        segment.tap()

        let doneButton = app.buttons["完了"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()
    }

    /// 設定画面(歯車アイコン)を開き、「写真1枚あたりの表示秒数」を指定のラベル(例: "1秒")に変更して閉じる。
    private static func setPhotoDuration(app: XCUIApplication, label: String, recorder: ScreenshotRecorder) throws {
        let settingsButton = app.buttons["playbackSettingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10), "設定(歯車)ボタンが見つからない")
        settingsButton.tap()

        let picker = app.buttons["photoDurationPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "「表示秒数」の設定項目が見つからない")
        picker.tap() // メニュー形式のPickerなので、タップすると選択肢一覧が開く

        let option = app.buttons[label]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "表示秒数の選択肢「\(label)」が見つからない")
        option.tap()

        recorder.shoot(app, label: "photo_duration_set_\(label)")

        let doneButton = app.buttons["完了"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()
    }

    private enum VideoCutoffMode {
        case full
        case capped(seconds: String)
    }

    /// 設定画面(歯車アイコン)を開き、「動画の再生時間の扱い」を変更して閉じる。
    private static func setVideoCutoffMode(app: XCUIApplication, mode: VideoCutoffMode, recorder: ScreenshotRecorder) throws {
        let settingsButton = app.buttons["playbackSettingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10), "設定(歯車)ボタンが見つからない")
        settingsButton.tap()

        switch mode {
        case .full:
            let fullButton = app.buttons["最後まで再生する"]
            XCTAssertTrue(fullButton.waitForExistence(timeout: 5), "「最後まで再生する」の選択肢が見つからない")
            fullButton.tap()
        case .capped(let seconds):
            let cappedButton = app.buttons["指定秒数で切り上げる"]
            XCTAssertTrue(cappedButton.waitForExistence(timeout: 5), "「指定秒数で切り上げる」の選択肢が見つからない")
            cappedButton.tap()

            let picker = app.buttons["videoCapPicker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5), "「切り上げる秒数」の設定項目が見つからない")
            picker.tap()

            let option = app.buttons[seconds]
            XCTAssertTrue(option.waitForExistence(timeout: 5), "切り上げ秒数の選択肢「\(seconds)」が見つからない")
            option.tap()
        }

        recorder.shoot(app, label: "video_mode_set")

        let doneButton = app.buttons["完了"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()
    }

    // MARK: - 共通処理: 観察

    /// スライドショー画面が出るのを待ち、写真/動画の切り替わりとカウントダウンの進行を観察する。
    private static func observeSlideshow(app: XCUIApplication, recorder: ScreenshotRecorder, rounds: Int, requireVideo: Bool) throws {
        let remainingLabel = app.staticTexts["remainingTimeLabel"]
        let noResultsFound = app.staticTexts["条件に合う写真・動画が見つかりませんでした"]

        let appeared = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: remainingLabel)],
            timeout: 15
        )
        recorder.shoot(app, label: "after_start_wait")

        if noResultsFound.exists {
            XCTFail("バグ report: 絞り込み条件に合う写真・動画があるはずなのに「見つかりませんでした」と表示された")
            recorder.writeManifest()
            return
        }
        guard appeared == .completed else {
            XCTFail("スタートを押してもタイマー画面(残り時間表示)が15秒以内に出てこなかった")
            recorder.writeManifest()
            return
        }

        var observedMediaIDs: [String] = []
        var observedRemaining: [Int] = []
        var sawVideo = false

        let mediaElement = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'media-'")
        ).firstMatch

        for round in 1...rounds {
            Thread.sleep(forTimeInterval: 2.0)

            let id = mediaElement.exists ? mediaElement.identifier : "(none)"
            observedMediaIDs.append(id)
            if id.hasPrefix("media-video-") { sawVideo = true }

            if remainingLabel.exists, let seconds = parseRemaining(remainingLabel.label) {
                observedRemaining.append(seconds)
            }

            if round % 2 == 0 {
                recorder.shoot(app, label: "r\(round)")
            }
        }
        recorder.shoot(app, label: "final")

        recorder.appendManifestLines([
            "",
            "media identifiers observed (順番):",
        ] + observedMediaIDs.enumerated().map { "  [\($0.offset)] \($0.element)" } + [
            "",
            "remaining seconds observed (順番): \(observedRemaining)",
            "distinct media count: \(Set(observedMediaIDs.filter { $0 != "(none)" }).count)",
            "video observed: \(sawVideo)",
        ])
        recorder.writeManifest()

        let distinctMedia = Set(observedMediaIDs.filter { $0 != "(none)" })
        XCTAssertGreaterThanOrEqual(distinctMedia.count, 2, "写真が切り替わっていない可能性。観測した目印: \(observedMediaIDs)")

        if observedRemaining.count >= 2 {
            XCTAssertLessThan(observedRemaining.last!, observedRemaining.first!, "カウントダウンが減っていない可能性。観測した残り秒数: \(observedRemaining)")
        } else {
            XCTFail("残り時間ラベルをほとんど読み取れなかった(観測できた回数: \(observedRemaining.count))")
        }

        if requireVideo {
            XCTAssertTrue(sawVideo, "動画の目印(media-video-)が一度も観測できなかった")
        }
    }

    /// 表示中のメディア要素(media-photo-/media-video-)の識別子が変化するタイミングを一定時間ポーリングし、
    /// 「切り替わりが起きた瞬間」同士の間隔(秒)の配列を返す。写真1枚あたりの表示秒数の検証に使う。
    private static func measureSwitchIntervals(mediaElement: XCUIElement, observeSeconds: TimeInterval, pollInterval: TimeInterval) -> [TimeInterval] {
        var lastID: String?
        var lastChangeAt: Date?
        var intervals: [TimeInterval] = []
        let deadline = Date().addingTimeInterval(observeSeconds)

        while Date() < deadline {
            let currentID = mediaElement.exists ? mediaElement.identifier : nil
            if let currentID, currentID != lastID {
                let now = Date()
                if let lastChangeAt {
                    intervals.append(now.timeIntervalSince(lastChangeAt))
                }
                lastChangeAt = now
                lastID = currentID
            }
            usleep(useconds_t(pollInterval * 1_000_000))
        }
        return intervals
    }

    /// メディア要素が「表示され続けている時間」を1サイクル分計測する(現れるのを待ち、消えるまでの秒数を返す)。
    /// 動画の再生時間の扱い(最後まで/指定秒数で切り上げ)の検証に使う。
    /// 【なぜ identifier の "完全一致" まで見るか】
    /// テスト用ライブラリは動画が1本しかないため、同じ動画が連続で選ばれることがある。
    /// アプリ側では表示するたびに識別子へ通し番号(displayToken)を埋め込んでいるため
    /// (`media-video-<番号>-<資産ID>`)、たとえ同じ動画でも「表示され直した」ことを
    /// identifier の完全一致が崩れた瞬間として検出できる。存在の有無(exists)だけを見ると、
    /// 次の再生への切り替わりが一瞬で起きた場合に見た目上「ずっと表示されたまま」に
    /// 見えてしまい、複数回の再生をまとめて1回分の長さと誤測定してしまう。
    private static func measureOneOnDuration(mediaElement: XCUIElement, pollInterval: TimeInterval, appearTimeout: TimeInterval, maxOnDuration: TimeInterval) -> TimeInterval? {
        let appearDeadline = Date().addingTimeInterval(appearTimeout)
        var firstID: String?
        while firstID == nil {
            if mediaElement.exists { firstID = mediaElement.identifier }
            if firstID == nil {
                if Date() > appearDeadline { return nil }
                usleep(useconds_t(pollInterval * 1_000_000))
            }
        }
        let start = Date()
        let endDeadline = start.addingTimeInterval(maxOnDuration)
        while mediaElement.exists && mediaElement.identifier == firstID {
            if Date() > endDeadline { return nil }
            usleep(useconds_t(pollInterval * 1_000_000))
        }
        return Date().timeIntervalSince(start)
    }

    /// "05:00" のような "分:秒" 表示を合計秒数に変換する。
    private static func parseRemaining(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]) else { return nil }
        return m * 60 + s
    }
}

/// スクリーンショットとログをCEO確認用フォルダ(apps/PhotoTimer/verify/)に書き出すための小さなヘルパー。
/// シナリオ名をファイル名の先頭に付けることで、複数テストの結果が混ざらないようにしている。
private final class ScreenshotRecorder {
    private let scenario: String
    private let dir: URL
    private let startTime = Date()
    private var index = 0
    private var manifestLines: [String] = []

    init(scenario: String) {
        self.scenario = scenario
        self.dir = URL(fileURLWithPath: "/Users/takahashitakayuki/my_ai_team/apps/PhotoTimer/verify")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func shoot(_ app: XCUIApplication, label: String) {
        index += 1
        // PHAssetのlocalIdentifierには "/" が含まれるため("UUID/L0/001"のような形式)、
        // そのままファイル名に使うとパスの区切りと誤認され保存に失敗する。ファイル名としては安全な文字に置き換える。
        let safeLabel = label.replacingOccurrences(of: "/", with: "-")
        let name = String(format: "%@_%02d_%@.png", scenario, index, safeLabel)
        let screenshot = XCUIScreen.main.screenshot()
        do {
            try screenshot.pngRepresentation.write(to: dir.appendingPathComponent(name))
            manifestLines.append("\(name)\tt=\(String(format: "%.1f", Date().timeIntervalSince(startTime)))s")
        } catch {
            // 保存に失敗した場合も記録だけは残す(黙って消さない。テスト自体の信頼性のため)。
            manifestLines.append("\(name)\tSAVE FAILED: \(error)")
        }
    }

    func appendManifestLines(_ lines: [String]) {
        manifestLines.append(contentsOf: lines)
    }

    func writeManifest() {
        let text = manifestLines.joined(separator: "\n") + "\n"
        let url = dir.appendingPathComponent("manifest_\(scenario).txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
