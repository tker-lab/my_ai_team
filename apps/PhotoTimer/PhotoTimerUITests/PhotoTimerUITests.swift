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
final class PhotoTimerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true // 1項目の失敗で残りの観察(スクリーンショット等)を打ち切らないため
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

        app.buttons["xmark.circle.fill"].firstMatch.tap() // 閉じるボタン(SF Symbol名がラベルになっている)
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
        } else {
            recorder.appendManifestLines(["許可ダイアログが検出できなかった。CEOに手動タップを依頼する運用にフォールバックが必要"])
        }
        // 許可の反映(ホーム画面への遷移)を待つ。
        _ = app.buttons["startButton"].waitForExistence(timeout: 5)
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
