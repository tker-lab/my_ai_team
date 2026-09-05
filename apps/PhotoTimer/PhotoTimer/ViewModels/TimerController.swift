import Foundation
import Photos
import AVKit
import AVFAudio
import AudioToolbox

/// タイマー本体とスライドショーの進行を管理する。
///
/// 「タイマー」と「スライドショー」は別々の時計を持つ:
///  - 全体のカウントダウン(ユーザーが設定した時間。例:10分)
///  - 1枚あたりの表示時間(写真は設定した秒数。動画は「最後まで再生」か「指定秒数で切り上げ」を設定で選べる)
/// カウントダウンが0になったら、今の1枚を最後にスライドショーを止め、アラーム音を鳴らす。
///
/// 【NSObjectを継承している理由】AVAudioPlayerの再生終了通知(AVAudioPlayerDelegate)を
/// 直接このクラスで受け取るため。AVAudioPlayerDelegateはNSObjectProtocolを前提とする
/// (Objective-C由来の)プロトコルのため、これに準拠するにはNSObjectのサブクラスである必要がある。
@MainActor
final class TimerController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    enum Phase: Equatable {
        case idle
        case running
        case finished
    }

    /// 「条件に合う写真・動画が1枚も見つからなかった」時の理由(指摘I: エラーの伝え方の改善)。
    enum NoCandidatesReason: Equatable {
        /// 絞り込み条件(日時・種類・アルバム・雰囲気・場所・カテゴリ)に合う写真・動画が
        /// そもそも1枚も無かった。
        case noMatchingPhotos
        /// 条件に合う写真・動画はあったが、1枚も読み込めなかった
        /// (iCloudからの取得失敗など。オフライン時にiCloud上にしかない写真だけが対象になった場合等)。
        case loadFailed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var totalSeconds: Int = 0
    @Published private(set) var currentAsset: PHAsset?
    @Published private(set) var currentImage: UIImage?
    @Published private(set) var currentPlayer: AVPlayer?
    /// 絞り込み条件に合う写真・動画が1枚も見つからなかった場合に理由が入る(見つかった場合は nil)。
    @Published private(set) var noCandidatesReason: NoCandidatesReason?
    /// 「今表示している1枚」が何回目の表示かを表す通し番号(0始まり、表示するたびに+1)。
    /// 候補が少ない(例:動画が1本しかない)場合、同じ写真・動画が連続して選ばれることがあり、
    /// その場合でも「切り替わった」ことが自動テスト(XCUITest)から見分けられるようにするための値。
    /// 画面の見た目には一切影響しない(アクセシビリティIDの一部としてのみ使う)。
    @Published private(set) var displayToken: Int = 0
    /// アラームが今まさに鳴っている(振動含む)かどうか。SlideshowViewが「アラームを止める」ボタンを
    /// 出すかどうかの判断に使う。CEO要望(2026-09-05):止めるまで鳴り続けるパターンを追加したため、
    /// 「今鳴っているか」を画面側が知る手段が必要になった。
    @Published private(set) var isAlarmSounding: Bool = false
    /// このタイマーで実際に表示できた項目。タイマー画面を閉じるとstop()で破棄する。
    @Published private(set) var displayedAssets: [PHAsset] = []
    /// 演出パターン(結婚式ムービー風・スタジアムビジョン風)が選ばれている時、「今どんな見せ方をしているか」。
    /// `.classic`(演出パターンを選ばない、これまで通りの表示)の時は常にnil。SlideshowViewはこの値が
    /// nilならこれまで通りcurrentImage/currentPlayerを描画し、非nilならこちらを優先して描画する。
    @Published private(set) var currentPresentationFrame: PresentationFrame?
    /// 【8-10対応】displayedAssetsに「すでに入っているか」をO(1)で調べるための索引。
    /// displayedAssetsの要素と常に一致するよう、追加・削除のたびに一緒に更新する
    /// (displayedAssetsを配列のまま=表示順を保ったまま振り返り一覧に使えるようにしつつ、
    /// 判定だけはSetで速くする、という二重持ちの構成)。
    /// 3時間・0.5秒間隔などの長時間設定だと、1枚判定するたびに配列を毎回線形探索
    /// (displayedAssets.contains(where:))していると、累積の計算量が写真の枚数の2乗に近づき
    /// 無視できなくなるため導入した。
    private var displayedAssetIDs: Set<String> = []

    /// 写真1枚あたりの表示秒数・動画の再生時間の扱い。CEO要望(2026-09-04)によりユーザー設定可能。
    /// `start(...)` の呼び出し時に渡された値をここに保持する(既定値は元の固定値と同じ)。
    private var playbackSettings: PlaybackSettings = .default
    /// アラームの鳴らし方(音色・n回/止めるまで・バイブレーション)。CEO要望(2026-09-05)によりユーザー設定可能。
    private var alarmSettings: AlarmSettings = .default

    /// 削除操作の結果をSlideshowViewに一時的に伝えるための値。
    /// 【なぜ必要か】削除の確認画面はOS標準のもの(iOSが必ず出す)なので、アプリ側で確認UIを
    /// 作る必要は無いが、「ユーザーが確認画面でキャンセルした」場合は何も起きない一方、
    /// 「本当に削除に失敗した」場合は理由をユーザーに伝えたい(CLAUDE.mdのチェック観点
    /// 「エラー時に何が起きたかが伝わるか」に対応)。発生のたびに新しい値(idが変わる)を入れることで、
    /// 表示側が「前回と同じ失敗をもう一度表示してしまう」ことなく、1回だけ通知として扱える。
    struct DeletionFailure: Identifiable, Equatable {
        let id = UUID()
    }
    @Published private(set) var deletionFailure: DeletionFailure?

    private var engine: CandidateEngine?
    private var runLoopTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    /// タイマーが終わる予定の絶対時刻。カウントダウンの計算(runCountdown)と、バックグラウンド
    /// 復帰時の「経過時間の正しい反映」(returnToForeground)の両方がこの1つの値を基準にする
    /// (CEO要望C. 2026-09-05:バックグラウンド動作)。
    private var deadline: Date?
    /// フィルタ画面で使う場所の選択肢(バックグラウンド復帰時にスライドループを再始動する際、
    /// CandidateEngineを作り直すために必要。start()呼び出し時の値をそのまま保持するだけ)。
    private var placeClusters: [PlaceCluster] = []

    // MARK: - 演出パターン(結婚式ムービー風・スタジアムビジョン風。2026-09-05追加)

    /// `start(...)` 呼び出し時の playbackSettings.presentationPattern をそのまま保持する。
    private var presentationPattern: PresentationPattern = .classic
    /// 今どの「間(ま)」まで進んだか(PresentationPattern.beatsのインデックス。巡回する)。
    private var patternBeatIndex = 0
    /// 「この間(ま)が求める種類(動画/写真)と違う候補が来た」時に、その候補を捨てずに
    /// 一時的に取っておく列。次にnextPrimaryAsset(engine:)が呼ばれた時、まずここから消費する
    /// (CandidateEngineへ2度取りに行かせない=同じ写真を失わないための仕組み)。
    private var pendingPrimaryQueue: [PHAsset] = []
    /// 「間」が求める種類の候補が来ず、連続でスキップした回数。1周(beats.count回)を超えて
    /// 一度も噛み合わなかった場合(例:「動画のみ」に絞り込んでいるのに写真前提の間ばかり続く等)、
    /// フリーズを避けるため種類を問わず強制的に表示する安全弁として使う。
    private var consecutiveSkippedBeats = 0

    /// - Parameter resumingUntil: 通常は nil(=今から`totalDurationSeconds`後に終わる、新規のタイマー開始)。
    ///   バックグラウンド中にアプリのプロセスごと終了し、その後の再起動で「前回のタイマー」を
    ///   再開する時だけ、前回計算済みの終了予定時刻(絶対時刻)をそのまま渡す
    ///   (これにより「経過時間を正しく反映」できる。RootView参照)。
    func start(totalDurationSeconds: Int, settings: FilterSettings, playbackSettings: PlaybackSettings, alarmSettings: AlarmSettings, placeClusters: [PlaceCluster], resumingUntil: Date? = nil) {
        stop()

        phase = .running
        displayedAssets = []
        displayedAssetIDs = []
        noCandidatesReason = nil
        totalSeconds = totalDurationSeconds
        self.playbackSettings = playbackSettings
        self.alarmSettings = alarmSettings
        self.placeClusters = placeClusters
        self.presentationPattern = playbackSettings.presentationPattern
        patternBeatIndex = 0
        pendingPrimaryQueue = []
        consecutiveSkippedBeats = 0
        currentPresentationFrame = nil

        let endDate = resumingUntil ?? Date().addingTimeInterval(TimeInterval(totalDurationSeconds))
        deadline = endDate
        remainingSeconds = max(0, Int(endDate.timeIntervalSinceNow.rounded()))

        // 【CEO要望C対応】バックグラウンドに回っていても「表示を正しく再開できる」ように、
        // 今動いているタイマーの情報を端末内に記録しておく。閉じた時(stop())に消す。
        RunningTimerStateStore.save(RunningTimerState(
            endDate: endDate,
            totalSeconds: totalDurationSeconds,
            filterSettings: settings,
            playbackSettings: playbackSettings,
            alarmSettings: alarmSettings
        ))
        // 【CEO要望C対応】バックグラウンド中でも指定時刻に音が鳴るよう、OS側(ローカル通知)に
        // 1件予約しておく。フォアグラウンドのまま普通に終わった場合はfinish()で取り消す。
        AlarmNotificationScheduler.scheduleAlarm(fireDate: endDate, tone: alarmSettings.tone)

        // 【2026-09-05追加:マナーモードで鳴らなかった不具合の対策の1つ】
        // 以前はタイマー終了の瞬間(finish())に初めて音声セッションのカテゴリを設定していた。
        // ここでカテゴリだけ先に"予約"しておく(setActiveはまだ呼ばない=他アプリの音楽を邪魔しない。
        // カテゴリを設定するだけでは他アプリの再生を止めない・ダッキングもしないため副作用が無い)。
        // こうすることで、実際にアラームを鳴らす瞬間に「初めてカテゴリを切り替える」という
        // 状態変化が起きなくなり、切り替え直後の一瞬だけ音が出ない可能性を減らす狙い。
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])

        // 【resumingUntilが既に過ぎていた場合】バックグラウンド中(またはプロセス終了中)に、
        // 本来ならとっくにタイマーが終わっていたケース。写真の検索・表示を始めるまでもなく、
        // 直接「タイマー終了」の状態にする(=戻ってきたら"即座に"しっかり表示する、という要望への対応)。
        // 【中4修正・2026-09-05】このケースは「ずっと前に終わったタイマーを、今アプリを開いた瞬間」
        // であり、鳴らすべき時刻(endDate)は既に過ぎている。その時刻に鳴らす役目はstart()で予約した
        // バックグラウンド用ローカル通知が既に正しく担っている(ローカル通知はOS側の責任で届くため、
        // プロセスが終了していても、開き直す前に既に鳴り終わっているはず)。ここでも同じ音を
        // 鳴らすと「何もしていないのにアプリを開いた瞬間から鳴り続ける」という二重鳴動になるため、
        // 音は鳴らさず「終了した」旨の表示だけにする。
        guard remainingSeconds > 0 else {
            finishWithoutSoundingAlarm()
            return
        }

        let engine = CandidateEngine(settings: settings, placeClusters: placeClusters)
        self.engine = engine

        countdownTask = Task { [weak self] in
            await self?.runCountdown()
        }
        runLoopTask = Task { [weak self] in
            await self?.runSlideLoop(engine: engine)
        }
    }

    func stop() {
        countdownTask?.cancel()
        runLoopTask?.cancel()
        countdownTask = nil
        runLoopTask = nil
        currentPlayer?.pause()
        currentPlayer = nil
        currentImage = nil
        currentPresentationFrame = nil
        currentAsset = nil
        displayedAssets = []
        displayedAssetIDs = []
        // 【2026-09-04追加】先読み(prefetchNext)は runLoopTask とは別の独立したTaskとして動いているため、
        // runLoopTask をキャンセルしただけではこの先読みタスクは止まらない。指摘Aで直した
        // 「✕で閉じたらすぐ裏の処理も止まる」を、先読み追加によって再び壊さないための後始末。
        if let engine {
            Task { await engine.cancelPrefetch() }
        }
        // 軽微指摘対応: 次回 start() まで前回の CandidateEngine を握ったままにしないよう nil に戻す
        // (機能上の実害は無いが、使い終わった実体を持ち続けない、という後始末を明確にする)。
        engine = nil
        deadline = nil
        phase = .idle
        // アラーム(音・バイブレーション)が鳴っている途中で閉じられた場合に備え、必ず止める。
        stopAlarm()
        // CEO要望C対応: 閉じた=もう再開する必要が無いタイマーなので、記録と予約通知の両方を消す。
        RunningTimerStateStore.clear()
        AlarmNotificationScheduler.cancelPendingAlarm()
    }

    // MARK: - バックグラウンド対応(CEO要望C. 2026-09-05)

    /// アプリがバックグラウンドに回った時に呼ぶ(SlideshowViewのscenePhase監視から)。
    /// 「裏にいる間は解析・表示を止める(電池を無駄に使わない)」を実現する:
    /// 写真・動画を探す/表示するループだけを止め、画面に出ていた画像・動画を手放す。
    /// カウントダウン自体(残り秒数の内部計算)は止めない
    /// (軽い処理であり、フォアグラウンド復帰時に正しい残り時間をすぐ計算し直せるようにするため。
    /// なお仮にOSがこのTaskごと一時停止させても、deadline〔絶対時刻〕基準で計算し直す設計〔runCountdown〕
    /// のため復帰後のズレは生じない)。バックグラウンド中に指定時刻へ鳴らす役目は
    /// start()で予約済みのローカル通知(AlarmNotificationScheduler)が担う。
    func enterBackground() {
        guard phase == .running else { return }
        runLoopTask?.cancel()
        runLoopTask = nil
        if let engine {
            Task { await engine.cancelPrefetch() }
        }
        currentPlayer?.pause()
        currentPlayer = nil
        currentImage = nil
        currentPresentationFrame = nil
    }

    /// アプリがフォアグラウンドに戻った時に呼ぶ。
    /// 「経過時間を正しく反映して表示を再開する」を実現する: deadline(絶対時刻)から
    /// 残り秒数を計算し直し、まだ残っていれば表示ループを再開する。
    /// 【中4修正・2026-09-05】すでに終わっていた場合、以前はここでアラームを鳴らしていたが、
    /// バックグラウンド中に鳴らす役目は既にローカル通知(AlarmNotificationScheduler)が
    /// 正しい時刻に果たし終えているため、ここで重ねて鳴らすと二重鳴動になる。
    /// 音は鳴らさず「終了した」旨の表示だけにする(finishWithoutSoundingAlarm参照)。
    func returnToForeground() {
        guard phase == .running, let deadline else { return }
        remainingSeconds = max(0, Int(deadline.timeIntervalSinceNow.rounded()))
        guard remainingSeconds > 0 else {
            finishWithoutSoundingAlarm()
            return
        }
        guard runLoopTask == nil, let engine else { return } // 既に動いている(=一瞬の切り替えだった)場合は何もしない
        runLoopTask = Task { [weak self] in
            await self?.runSlideLoop(engine: engine)
        }
    }

    // MARK: - 写真・動画の削除(CEO要望 D. 2026-09-05)

    /// 今表示している1枚をその場で削除する。
    ///
    /// 【誤削除が起きない理由】ここでは「削除したい」という意思表示(`PHAssetChangeRequest.deleteAssets`)
    /// をOSに伝えるだけで、実際の削除はiOS標準の確認ダイアログ(「写真を削除」/「キャンセル」)を
    /// ユーザーが自分で選んだ場合にのみ実行される。この確認ダイアログはPhotosフレームワーク側が
    /// 自動的に出すものでアプリ側で省略・自作することはできない(=CEO要望どおり、OS標準の
    /// 仕組みをそのまま使っている。アプリ側の不具合で「確認なしに消える」ことは原理的に起こらない)。
    ///
    /// 【将来の課金機能との切り分け】このボタンを見せるかどうかの判定はSlideshowView側で
    /// `FeatureFlags.isPhotoDeletionEnabled` を見て行っている(このメソッド自体はフラグを見ない)。
    /// 課金者限定にしたくなったら、そのフラグの中身だけを差し替えればよい(詳細はFeatureFlags.swift参照)。
    func deleteAssets(_ assets: [PHAsset]) {
        guard phase == .finished, !assets.isEmpty else { return }
        let identifiersToDelete = assets.map(\.localIdentifier)

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }, completionHandler: { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                if success {
                    // 端末内に蓄積した色・カテゴリの解析結果も一緒に片付ける(もう存在しない写真の
                    // 判定結果を持ち続けても無駄なだけなので。AnalysisCacheは別actorなので
                    // ここではawaitせず投げっぱなしにして良い=削除完了の体感速度に影響させない)。
                    Task.detached(priority: .utility) {
                        await AnalysisCache.shared.removeAnalyses(for: identifiersToDelete)
                    }
                    let deleted = Set(identifiersToDelete)
                    self.displayedAssets.removeAll { deleted.contains($0.localIdentifier) }
                    self.displayedAssetIDs.subtract(deleted)
                } else if error != nil {
                    // success=false かつ error が nil の場合は「ユーザーが確認ダイアログでキャンセルした」
                    // という正常系(Appleの仕様どおり)であり、何もしない(=表示を続ける)のが正しい。
                    // ここに来るのは本当に削除できなかった場合(iCloud同期の都合等)だけなので、
                    // その時だけユーザーに知らせる(指摘対応: エラー時に何が起きたか伝わるようにする)。
                    NSLog("[PhotoTimer] 写真・動画の削除に失敗しました: \(error!)")
                    self.deletionFailure = DeletionFailure()
                }
            }
        })
    }

    /// 削除失敗のアラートを閉じた後、同じ内容をもう一度表示しないようにするための後始末。
    func clearDeletionFailure() {
        deletionFailure = nil
    }

    /// 【軽微指摘対応: カウントダウンが実時間からズレていく不具合】
    /// 以前は「1秒スリープして1引く」を繰り返すだけだったため、スリープ自体のわずかなオーバーヘッド
    /// (OSのスケジューリングの都合など)が毎回積み重なり、タイマーが長いほど実際の経過時間より
    /// 表示上の残り時間の減りが遅くなっていく(実時間とズレる)不具合があった。
    /// 今は「開始時刻から数えて本来あと何秒か」を毎回時計(Date)から計算し直すことで、
    /// 1回ごとのズレが蓄積しないようにしている。
    /// 【2026-09-05変更】deadlineをこのメソッド内のローカル変数からTimerControllerのプロパティに
    /// 昇格した(CEO要望C:バックグラウンド復帰時にreturnToForeground()からも同じ基準時刻を
    /// 参照する必要があるため)。計算方法自体は変えていない。
    private func runCountdown() async {
        while let deadline, remainingSeconds > 0 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            remainingSeconds = max(0, Int(deadline.timeIntervalSinceNow.rounded()))
        }
        finish()
    }

    /// 鳴らしている間、参照を保持しておくためのプレイヤー(手放すと即座に無音で止まってしまうため)。
    private var alarmPlayer: AVAudioPlayer?
    /// バイブレーションを繰り返すためのTask(止めるまで鳴り続ける/n回パターンの間、一定間隔で振動させる)。
    private var vibrationTask: Task<Void, Never>?

    private func finish() {
        guard phase == .running else { return }
        phase = .finished
        runLoopTask?.cancel()
        currentPlayer?.pause()
        playAlarm()
        // 【CEO要望C対応】ここに来た時点で(フォアグラウンドの、いつも通りの繰り返しパターンで)
        // アラームを鳴らし始めたので、バックグラウンド用に予約していたローカル通知は不要になる
        // (鳴らさずに済ませることで、後から二重に音が鳴るのを防ぐ)。
        AlarmNotificationScheduler.cancelPendingAlarm()
    }

    /// 【中4修正・2026-09-05】「復帰した時点で、鳴るべき時刻を既に過ぎていた」場合に使う、
    /// 音を鳴らさないバージョンのfinish()。
    /// 呼び出し元は2箇所: ①アプリ自体が終了していて、再び開いた直後(start()のresumingUntil)
    /// ②バックグラウンドに回っていただけで、フォアグラウンドに戻った直後(returnToForeground())。
    /// どちらの場合も「鳴らすべき時刻」には既にローカル通知(AlarmNotificationScheduler)が
    /// 正しく音を鳴らし終えているはずなので、ここで改めてplayAlarm()を呼ぶと、
    /// ユーザーが何もしていないのに「アプリを開いた瞬間」に音・バイブレーションが鳴り出す
    /// (=本来鳴るべきタイミングより後ろにずれた、二重の鳴動)という不具合になっていた。
    /// 音は鳴らさず、finish()と同様に「終了した」状態(表示)にするだけに留める。
    private func finishWithoutSoundingAlarm() {
        guard phase == .running else { return }
        phase = .finished
        runLoopTask?.cancel()
        currentPlayer?.pause()
        AlarmNotificationScheduler.cancelPendingAlarm()
    }

    /// アラーム(音・バイブレーション)を鳴らし始める。
    ///
    /// 【2026-09-04再調査 → 2026-09-05再々調査:マナーモード(消音スイッチ)でアラームが聞こえない件】
    /// 1回目の調査で、`AudioServicesPlaySystemSound`(短い操作音向けのAPI)はアプリの音声セッションの
    /// 種類(カテゴリ)を一切見ない仕様だと判明し、実際の音声データを `AVAudioPlayer` で
    /// (.playback カテゴリのセッションの下で)再生する方式に変更した。ここまでは正しい対応だったが、
    /// それでも実機でまだ鳴らないというCEOからの再報告を受け、さらに以下の2点を強化した。
    ///  1. カテゴリの設定自体は `start()` の時点(タイマー開始時)で先に済ませておき、ここでは
    ///     `setActive(true)`(実際に音を出す権利を得る操作)だけを行うようにした。実機では
    ///     「カテゴリの切り替え」と「アクティブ化」を同時に行うと、ハードウェア側の準備が
    ///     間に合わず最初の一瞬だけ無音になることがある、という報告が実際にあるため、
    ///     切り替えのタイミングを早めることでこのリスクを下げる狙い。
    ///  2. `try?` で例外を握りつぶさず、失敗した場合はコンソールログに理由を残すようにした
    ///     (次にまだ鳴らない場合の切り分けを速くするため)。
    ///  3. 今回追加した「n回鳴って終わる/止めるまで鳴り続ける」機能により、音を1回きりではなく
    ///     繰り返し再生するようになった。仮に最初の1回に何らかの再生開始の遅延があっても、
    ///     2回目以降は音声セッションが安定した状態で再生されるため、結果的に「聞こえない」
    ///     状況そのものが起こりにくくなる。
    private func playAlarm() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            isAudioSessionActive = true
        } catch {
            NSLog("[PhotoTimer] アラーム用の音声セッションの設定に失敗しました: \(error)")
        }

        if let player = try? AVAudioPlayer(data: AlarmTone.data(for: alarmSettings.tone)) {
            player.delegate = self
            switch alarmSettings.repeatMode {
            case .untilStopped:
                player.numberOfLoops = -1 // 負の値 = 明示的に止めるまで無限に繰り返す
            case .times(let count):
                player.numberOfLoops = max(0, count - 1) // numberOfLoops=0で「1回だけ」再生される
            }
            player.volume = 1.0
            player.prepareToPlay()
            player.play()
            alarmPlayer = player
            isAlarmSounding = true
        } else {
            // 万一 AVAudioPlayer の生成に失敗した場合の保険。マナーモード次第では聞こえないが、
            // 何も鳴らないよりはまし、という位置づけで従来のシステムサウンドを1回だけ鳴らしておく。
            NSLog("[PhotoTimer] AVAudioPlayerの生成に失敗したため、フォールバックのシステムサウンドを再生します")
            AudioServicesPlaySystemSound(1005)
        }

        if alarmSettings.useVibration {
            startVibrationLoop()
        }
    }

    /// バイブレーションを一定間隔(音のワンサイクルに近い長さ)で繰り返す。
    /// 【実機確認事項への回答】バイブレーションは消音スイッチの影響を受けない
    /// (影響するのは「設定→サウンドと触覚→消音時のバイブレーション」がオフの場合のみで、
    /// これは端末側の任意設定でありアプリからは検知・変更できない)。
    private func startVibrationLoop() {
        stopVibrationLoop()
        vibrationTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                try? await Task.sleep(nanoseconds: 1_300_000_000)
            }
        }
    }

    private func stopVibrationLoop() {
        vibrationTask?.cancel()
        vibrationTask = nil
    }

    /// アラーム(音・バイブレーション)を止める。CEO要望(2026-09-05):
    /// 「止めるまで鳴り続ける」パターンを止めるための操作として、SlideshowViewのボタンから呼ばれる。
    /// タイマーを終了させずに閉じた時(stop())からも呼ばれる、後始末の共通口。
    func stopAlarm() {
        alarmPlayer?.stop()
        alarmPlayer = nil
        isAlarmSounding = false
        stopVibrationLoop()
        deactivateAudioSessionIfNeeded()
    }

    /// AVAudioPlayerDelegate: 「n回鳴って終わる」パターンで、ユーザーが止める前に指定回数を
    /// 再生し終えて自然に音が止まった時に呼ばれる(手動でstop()した時はこのメソッドは呼ばれない。
    /// Appleの仕様どおり)。ここで isAlarmSounding を false に戻すことで、
    /// SlideshowView側のボタン表示が「アラームを止める」から「閉じる」へ自動的に切り替わる。
    /// AVAudioPlayerDelegateはNSObjectProtocol由来でMainActor隔離が付いていないプロトコルのため、
    /// `nonisolated` にした上で内部で明示的にMainActorへ処理を渡す。
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.alarmPlayer === player else { return }
            self.isAlarmSounding = false
            self.stopVibrationLoop()
            self.deactivateAudioSessionIfNeeded()
            self.alarmPlayer = nil
        }
    }

    /// スライドショーの本体ループ。
    ///
    /// 【2026-09-04修正(指摘B対応): 該当0件で無限ループして固まる不具合】
    /// 修正前は「シャッフル済みの候補を使い切ったら、無条件に prepare() → continue」としていたため、
    /// 「絞り込み条件(雰囲気・カテゴリ)に合う写真が1枚も無い」ケースでは
    ///   prepare()(候補は取れる)→ next()を全部試すが1枚も条件に合わず nil → prepare() → …
    /// を無限に繰り返し、CPUを使い切ったまま「読み込み中…」から進まなくなっていた
    /// (日時・種類・アルバム・場所の時点では絞り込めても、雰囲気・カテゴリは1枚ずつ判定する
    /// 遅延評価〔原則2〕のため、その時点ではまだ0件と分からない)。
    ///
    /// 今は「1周(prepareしてからnext()がnilを返すまで)の間に1枚でも実際に表示できたか」を
    /// 必ず記録し、1枚も表示できなかった1周が終わった時点で確実に止める。同じ絞り込み条件・
    /// 同じ写真ライブラリでは何周しても結果は変わらない(判定は決定的)ため、これで無限ループは起きない。
    ///
    /// 【8-5対応・2026-09-05】「1周し終えるまで待つ」だけだと、該当が0件の条件を大きな写真ライブラリ
    /// (実機実測で6045枚・キャッシュ無しの全走査に185.78秒)で試した時、「読み込み中…」のまま
    /// 数分間なにも変わらない状態になりうる。**「探しています」のような途中経過の表示は入れない**
    /// (CEO指示)。代わりに、1枚も表示できないまま`zeroResultSearchTimeout`だけ経過したら、
    /// たとえ1周を終えていなくても「一巡した」時と同じ終わり方(見つかりませんでした/読み込めません
    /// でした)で静かに確定させる。1周を待たずに終える分だけ「本当は該当があった」を見逃す
    /// 可能性はゼロではないが、判定結果は解析キャッシュに逐次保存されているため(8-2対応)、
    /// 次回同じ条件で試した時はキャッシュ済みの分だけ速く先に進める=使うほど機会を取りこぼしにくくなる。
    /// 【8-5対応】1枚も表示できていない探索をこの時間だけ試して、それでも見つからなければ
    /// 一周し終えていなくても諦める上限。実機実測(全走査185.78秒/6045枚)を踏まえ、
    /// 「数分待たせる」ことは避けつつ、キャッシュが無い1回目でもある程度は探せる長さとして選んだ。
    private static let zeroResultSearchTimeout: Duration = .seconds(20)

    private func runSlideLoop(engine: CandidateEngine) async {
        await engine.prepare()
        if await engine.candidatePoolCount == 0 {
            // 日時・種類・アルバム・場所の時点(メタ情報のみ)ですでに0件。原則2の対象外なので即座に確定できる。
            showNoCandidates(reason: .noMatchingPhotos)
            return
        }

        while phase == .running, !Task.isCancelled {
            var sawAnyCandidateThisPass = false // 雰囲気・カテゴリの条件に合う写真が1枚でもあったか
            var displayedAnyThisPass = false // 実際に1枚でも表示できたか(読み込み失敗を除く)
            let passStartedAt = ContinuousClock.now // 8-5対応: この1周にかけている時間を計るため

            innerLoop: while phase == .running, !Task.isCancelled {
                // 【2026-09-05追加:演出パターン】presentationPatternが.classic以外の時は、
                // 固定の「間」の並び(PresentationPattern.beats)に沿って表示する。performNextStep(engine:)
                // が「1枚(または1組)取得して表示する/この間はスキップする/候補が尽きた」を判定する。
                switch await performNextStep(engine: engine) {
                case .exhausted(let hasPendingWork):
                    // 18件/0.8秒の探索予算で一旦区切っただけなら、UIへ制御を返して次の呼び出しで続行。
                    // nilを「全件0」と誤解してタイマーを終了しない。
                    if hasPendingWork {
                        // 【8-5対応】1枚も表示できないまま探索がzeroResultSearchTimeoutを超えたら、
                        // 候補プールを一周し終えていなくてもここで諦める(下の「1周しても1枚も
                        // 表示できなかった」分岐へ進み、静かに終わる)。大きな写真ライブラリで
                        // 該当0件の条件だと、律儀に一周し終えるまで待つと数分かかることがあるため。
                        if !displayedAnyThisPass, passStartedAt.duration(to: .now) >= Self.zeroResultSearchTimeout {
                            break innerLoop
                        }
                        await Task.yield()
                        continue innerLoop
                    }
                    break innerLoop
                case .skippedBeat:
                    // 「間」が求める種類(動画/写真)と違う候補だった。時間は消費せず次の「間」へ進む。
                    sawAnyCandidateThisPass = true
                    continue innerLoop
                case .displayed(let displayed):
                    sawAnyCandidateThisPass = true
                    if displayed {
                        displayedAnyThisPass = true
                        // 【8-10対応】以前はここで毎回displayedAssets(配列)を線形探索していた。
                        // displayedAssetIDs(Set)で先にO(1)判定してから、表示順を保つための配列にも追加する。
                        if let asset = currentAsset, displayedAssetIDs.insert(asset.localIdentifier).inserted {
                            displayedAssets.append(asset)
                        }
                    }
                }
            }

            if Task.isCancelled || phase != .running { return }

            if !displayedAnyThisPass {
                // 1周しても1枚も表示できなかった。もう一度シャッフルし直しても結果は変わらないため、ここで止める。
                // 【指摘H対応】「条件に合う候補が無かった(noMatchingPhotos)」と「判定・表示できなかった
                // だけ(loadFailed)」を混同しないようにする。以前は sawAnyCandidateThisPass
                // (=雰囲気・カテゴリの判定に実際に合格した候補があったか)だけを見ていたため、
                // 「判定用サムネイルがそもそも取得できず、合否を判定できないまま読み飛ばした」
                // ケース(engine.hadUndeterminedCandidates)が noMatchingPhotos 側に紛れ込んでいた。
                let hadUndeterminedCandidates = await engine.hadUndeterminedCandidates
                let reason: NoCandidatesReason
                if sawAnyCandidateThisPass || hadUndeterminedCandidates {
                    reason = .loadFailed
                } else {
                    reason = .noMatchingPhotos
                }
                showNoCandidates(reason: reason)
                return
            }

            // 少なくとも1枚は表示できたので、末尾まで来たら最初からシャッフルし直して続ける(ランダム再生をループさせる)。
            await engine.prepare()
        }
    }

    private func showNoCandidates(reason: NoCandidatesReason) {
        noCandidatesReason = reason
        phase = .finished
        countdownTask?.cancel()
    }

    // MARK: - 演出パターン(結婚式ムービー風・スタジアムビジョン風)の1ステップ

    /// runSlideLoopの内側ループが1回に行う仕事の結果。
    private enum StepOutcome {
        /// 実際に表示を試みた(true=表示できた、false=読み込み失敗で何も表示できなかった)。
        case displayed(Bool)
        /// この「間」が求める種類(動画/写真)の候補が今は無かったため、時間を使わずスキップした。
        case skippedBeat
        /// 候補プールを使い切った、または探索予算で一旦区切られた。
        case exhausted(hasPendingWork: Bool)
    }

    /// 候補を1つ取り出す。前回「間」と噛み合わず取っておいた候補(pendingPrimaryQueue)があれば
    /// それを優先し、無ければCandidateEngineへ新しく問い合わせる。
    private func nextPrimaryAsset(engine: CandidateEngine) async -> PHAsset? {
        if !pendingPrimaryQueue.isEmpty {
            return pendingPrimaryQueue.removeFirst()
        }
        return await engine.next()
    }

    /// runSlideLoopの内側ループを1回進める。
    /// `presentationPattern == .classic` の時はこれまで通り(1枚取得してそのまま表示するだけ)。
    /// 演出パターンが選ばれている時は、固定の「間」の並びに沿って処理する。
    private func performNextStep(engine: CandidateEngine) async -> StepOutcome {
        guard presentationPattern != .classic else {
            guard let asset = await nextPrimaryAsset(engine: engine) else {
                return .exhausted(hasPendingWork: await engine.hasPendingSearchWork)
            }
            if Task.isCancelled { return .displayed(false) }
            currentAsset = asset
            displayToken += 1
            await engine.prefetchNext()
            let displayed = await displayAndWait(asset: asset, overrideDuration: nil)
            return .displayed(displayed)
        }

        let beats = presentationPattern.beats
        let beat = beats[patternBeatIndex % beats.count]

        guard let asset = await nextPrimaryAsset(engine: engine) else {
            return .exhausted(hasPendingWork: await engine.hasPendingSearchWork)
        }
        if Task.isCancelled { return .displayed(false) }

        guard (asset.mediaType == .video) == beat.content.isVideo else {
            // 【共通要件対応:動画前提の「間」に動画候補が無ければスキップ】
            // この候補は今の「間」には合わないだけで、後の「間」(動画/写真、いずれかいつか噛み合う方)
            // で使えるかもしれないので取っておく(捨てない)。
            consecutiveSkippedBeats += 1
            if consecutiveSkippedBeats > beats.count {
                // 1周(beats.count回)を超えても一度も噛み合わなかった(例:「動画のみ」に
                // 絞り込んでいるのに写真前提の間ばかり続く等)。フリーズを避けるため、
                // この候補を種類を問わずそのまま表示して仕切り直す。
                consecutiveSkippedBeats = 0
                currentAsset = asset
                displayToken += 1
                await engine.prefetchNext()
                let displayed = await displayAndWait(asset: asset, overrideDuration: beat.duration)
                patternBeatIndex += 1
                return .displayed(displayed)
            }
            pendingPrimaryQueue.append(asset)
            patternBeatIndex += 1
            return .skippedBeat
        }

        consecutiveSkippedBeats = 0
        currentAsset = asset
        displayToken += 1
        await engine.prefetchNext()
        let displayed = await displayForBeat(beat, primary: asset, engine: engine)
        patternBeatIndex += 1
        return .displayed(displayed)
    }

    /// 演出パターンの「間」1つぶんを表示する(写真フルスクリーン・コラージュ・動画のいずれか)。
    private func displayForBeat(_ beat: PresentationBeat, primary: PHAsset, engine: CandidateEngine) async -> Bool {
        currentPlayer?.pause()
        currentPlayer = nil
        currentImage = nil
        currentPresentationFrame = nil

        switch beat.content {
        case .video:
            guard let playerItem = await Self.requestPlayerItem(for: primary) else { return false }
            if Task.isCancelled { return false }
            let player = AVPlayer(playerItem: playerItem)
            currentPlayer = player
            configureAudioForVideoPlayback(player: player) // 音の3択設定は演出パターンでも変わらない
            player.play()
            // 【CEO決定・2026-09-05】演出パターンが選ばれている時は、動画の再生秒数も
            // ユーザーの設定(videoPlaybackMode/videoCapSeconds)ではなく、この「間」自身が
            // 決めた秒数(beat.duration)を使う。
            await Self.waitForVideoToFinish(player: player, timeout: beat.duration)
            player.pause()
            return true

        case .photoFullScreen(let style):
            deactivateAudioSessionIfNeeded()
            guard let image = await Self.requestDisplayImage(for: primary) else { return false }
            if Task.isCancelled { return false }
            currentImage = image
            currentPresentationFrame = PresentationFrame(
                layout: .fullScreen(image: image, assetID: primary.localIdentifier, style: style),
                transition: beat.transition
            )
            try? await Task.sleep(nanoseconds: UInt64(max(0.1, beat.duration) * 1_000_000_000))
            return true

        case .photoCollage(let secondaryCount, let arrangement):
            deactivateAudioSessionIfNeeded()
            guard let mainImage = await Self.requestDisplayImage(for: primary) else { return false }
            if Task.isCancelled { return false }
            currentImage = mainImage
            var secondaries: [(image: UIImage, assetID: String)] = []
            for _ in 0..<secondaryCount {
                guard let extraAsset = await fetchSecondaryPhotoAsset(engine: engine) else { break }
                guard let extraImage = await Self.requestDisplayImage(for: extraAsset) else { continue }
                secondaries.append((extraImage, extraAsset.localIdentifier))
                recordDisplayed(extraAsset)
            }
            if secondaries.isEmpty {
                // 追加候補が1枚も用意できなかった(候補プールがほぼ尽きた等)。原則「必ず何か出す」に
                // 沿って、コラージュを諦めて1枚のフルスクリーンにフォールバックする(クラッシュ・
                // 空白表示にはしない)。
                currentPresentationFrame = PresentationFrame(
                    layout: .fullScreen(image: mainImage, assetID: primary.localIdentifier, style: .kenBurns),
                    transition: beat.transition
                )
            } else {
                currentPresentationFrame = PresentationFrame(
                    layout: .collage(main: (mainImage, primary.localIdentifier), secondaries: secondaries, arrangement: arrangement),
                    transition: beat.transition
                )
            }
            try? await Task.sleep(nanoseconds: UInt64(max(0.1, beat.duration) * 1_000_000_000))
            return true
        }
    }

    /// コラージュ・モザイクの「小さい方」の写真を1枚取得する。動画が来た場合は、後の「間」
    /// (動画前提の間)で使えるように取っておき、ここでは使わない(nilを返す=コラージュの枠が1つ減る)。
    private func fetchSecondaryPhotoAsset(engine: CandidateEngine) async -> PHAsset? {
        guard let candidate = await engine.next() else { return nil }
        if candidate.mediaType == .video {
            pendingPrimaryQueue.append(candidate)
            return nil
        }
        return candidate
    }

    /// コラージュの脇役として表示した写真も、振り返り一覧(displayedAssets)に記録しておく
    /// (実際にユーザーの目に触れたものなので、主役級の1枚と同じ扱いにする)。
    private func recordDisplayed(_ asset: PHAsset) {
        if displayedAssetIDs.insert(asset.localIdentifier).inserted {
            displayedAssets.append(asset)
        }
    }

    /// 1枚(1本)を表示し、表示時間だけ待つ。実際に表示できた場合は true、
    /// 読み込みに失敗して何も表示できなかった場合は false を返す(指摘B・I対応)。
    /// - Parameter overrideDuration: nilの時はこれまで通りplaybackSettingsの秒数を使う。
    ///   非nilの時はその秒数を使う(演出パターンが「間」と噛み合わない候補を強制表示する時のみ使用)。
    @discardableResult
    private func displayAndWait(asset: PHAsset, overrideDuration: TimeInterval?) async -> Bool {
        currentPlayer?.pause()
        currentPlayer = nil
        currentImage = nil
        currentPresentationFrame = nil

        switch asset.mediaType {
        case .video:
            guard let playerItem = await Self.requestPlayerItem(for: asset) else { return false }
            if Task.isCancelled { return false }
            let player = AVPlayer(playerItem: playerItem)
            currentPlayer = player
            configureAudioForVideoPlayback(player: player) // CEO要望(2026-09-05): 動画の音と他アプリの音楽の関係(3択)
            player.play() // 動画は音付きで再生(MVP必須要件。ただし設定次第でミュートすることがある)
            // 「指定秒数で切り上げる」設定の時だけ上限を設ける。「最後まで再生する」設定の時は上限なし(nil)。
            let timeout: TimeInterval? = overrideDuration ?? (playbackSettings.videoPlaybackMode == .capped ? playbackSettings.videoCapSeconds : nil)
            await Self.waitForVideoToFinish(player: player, timeout: timeout)
            player.pause()
            // 【軽微指摘対応】ここでは手放さない。以前はここで毎回 deactivate していたため、
            // 動画が連続して選ばれた時に「手放す→次の動画のために確保し直す」を動画ごとに
            // 繰り返してしまい、そのたびに他アプリ(音楽アプリ等)の再生が一瞬止まって
            // また再開する、を動画の本数だけ繰り返す不具合があった。
            // 手放すのは「次に表示するのが動画ではなかった時」(下のdefault節)か、
            // スライドショー自体を終了する時(stop())にまとめて行う。
            return true
        default:
            // 直前まで動画が続いていた場合、写真に切り替わったタイミングで音声セッションを手放す
            // (動画を再生する瞬間"だけ"確保する、という指摘D対応の元々の意図はここで保つ)。
            deactivateAudioSessionIfNeeded()
            guard let image = await Self.requestDisplayImage(for: asset) else { return false }
            if Task.isCancelled { return false }
            currentImage = image
            // 【8-8対応】UIからは1秒未満・0以下・NaNには到達しないはずだが、万一そのような値が
            // 設定ファイルに入っていた場合、UInt64(...)への変換がクラッシュ(トラップ)する
            // (0以下やNaNは負の数・不正な値としてUInt64の範囲外になるため)。念のため
            // 最低0.1秒を下限にクランプしておく(実用上ここに到達しなくても安全側に倒すだけの保険)。
            let rawDuration = overrideDuration ?? playbackSettings.photoSlideDurationSeconds
            let safeSlideSeconds = rawDuration.isFinite ? max(0.1, rawDuration) : 0.1
            try? await Task.sleep(nanoseconds: UInt64(safeSlideSeconds * 1_000_000_000))
            return true
        }
    }

    // MARK: - 音声セッション(指摘D対応 + 軽微指摘対応 + CEO要望2026-09-05:動画の音と他アプリの音楽の関係)

    /// 今、音声セッション(動画の音を鳴らすための権利のようなもの)を確保している最中かどうか。
    /// これを見て「すでに確保済みなら何もしない/まだ確保していなければ確保する」を判断することで、
    /// 動画が連続する時に毎回 確保→解放 を繰り返さないようにする。
    private var isAudioSessionActive = false

    /// 【2026-09-05追加】設定(playbackSettings.videoAudioMixMode)に応じて、動画を再生する
    /// 直前に音声セッションをどう扱うか・動画自体をミュートするかを決める。
    ///
    /// 【なぜ音声セッションだけでなくAVPlayer自体もミュートするのか】
    /// 「音楽が鳴っている時は動画を無音にする」を実現するには、動画側の音声セッションを
    /// 確保しないだけでは不十分。仮にセッションを確保しないままplayer.play()すると、
    /// AVPlayerはアプリの現在の音声セッション(前の動画で確保したまま、あるいはOS既定)の
    /// 設定に従って音を出そうとしてしまう場合があるため、`player.isMuted` で動画自体を
    /// 確実に無音にする(=この動画の音だけを止める。他アプリの音楽には一切触れない)。
    ///
    /// 【なぜ「無音にする」時に音声セッションを手放すのか】
    /// `.playback` カテゴリ(mixWithOthers/duckOthers指定なし)のセッションは、鳴らす音自体を
    /// ミュートしていても「確保している」だけで他アプリの音声を止める・再開させない力を持つ
    /// (Appleの排他的カテゴリの仕様)。前の動画が「音楽オフ」の時に再生されてセッションを
    /// 確保したまま、次の動画で「音楽がオン」に変わっていた場合、セッションを手放さずに
    /// ミュートするだけでは音楽が鳴らない(邪魔したまま)ままになってしまう。
    /// 「muteWhenOtherAudioPlaying」で無音にする時は必ずセッションも手放すことで、
    /// 「本当に何もしていない(音楽を一切邪魔しない)」状態を保証する。
    ///
    /// 【アラームへの影響は無い】ここで扱うのは動画再生用のセッションのみで、アラーム
    /// (TimerController.playAlarm)は別の場所で常に `.duckOthers` を使う。この3択のどれを
    /// 選んでも、アラームがマナーモードでも鳴る挙動(CEO実機確認済み)は変えない。
    private func configureAudioForVideoPlayback(player: AVPlayer) {
        switch playbackSettings.videoAudioMixMode {
        case .mixWithOthers:
            activateAudioSessionIfNeeded(options: [.mixWithOthers])
            player.isMuted = false
        case .duckOthers:
            activateAudioSessionIfNeeded(options: [.duckOthers])
            player.isMuted = false
        case .muteWhenOtherAudioPlaying:
            if AVAudioSession.sharedInstance().isOtherAudioPlaying {
                // 他アプリの音楽を一切邪魔しない: セッションを手放し、この動画だけ無音にする。
                deactivateAudioSessionIfNeeded()
                player.isMuted = true
            } else {
                // 他に鳴っている音が無いので、通常どおり音を出す(ダッキング等の特別な指定は不要)。
                activateAudioSessionIfNeeded(options: [])
                player.isMuted = false
            }
        }
    }

    /// 動画を再生する瞬間だけ音声セッションを確保する。すでに確保済みなら何もしない
    /// (動画が連続する時に、動画ごとに確保し直して他アプリの音楽を毎回止めてしまうのを防ぐ)。
    /// 【なぜ「アプリ起動時にまとめて確保」から「再生の瞬間だけ」に変えたか】
    /// 以前は PhotoTimerApp の起動時(init)に確保しっぱなしにしていたため、フィルタ画面を見ているだけ、
    /// あるいはタイマーを設定しているだけでも他アプリ(音楽アプリ等)の再生が強制的に止まってしまう
    /// 不具合があった(指摘D)。動画を再生する瞬間だけ確保することで、写真だけが流れている間や
    /// タイマーを使っていない間は他アプリの音楽を邪魔しない。
    /// - Parameter options: `.mixWithOthers`(両方そのまま鳴らす)/ `.duckOthers`(他を小さくする)/
    ///   空(特に何も指定しない。他に鳴っている音が無い時用)。CEO要望(2026-09-05)の3択に対応するため
    ///   呼び出し側(configureAudioForVideoPlayback)が選ぶ。
    private func activateAudioSessionIfNeeded(options: AVAudioSession.CategoryOptions) {
        guard !isAudioSessionActive else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: options)
        try? AVAudioSession.sharedInstance().setActive(true)
        isAudioSessionActive = true
    }

    /// 音声セッションを手放す。すでに手放し済みなら何もしない。`.notifyOthersOnDeactivation` を
    /// 指定することで、一時停止していた他アプリの音楽に「再開してよい」ことを伝える
    /// (Appleの推奨パターン)。
    private func deactivateAudioSessionIfNeeded() {
        guard isAudioSessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isAudioSessionActive = false
    }

    // MARK: - 画像・動画の取得

    private static func requestDisplayImage(for asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true // 本人のiCloud上の写真も表示できるようにする(仮の判断。詳細は報告参照)
        options.resizeMode = .fast

        // 【軽微指摘対応】UIScreen.main はiOS 16以降非推奨(複数ウィンドウに対応したアプリでは
        // 「画面は1つ」を前提にするこのAPIが実態に合わないため)。代わりに、今つながっている
        // ウィンドウシーンから画面情報を取る。TimerController全体が@MainActorなので、
        // UIApplication.sharedへここで直接アクセスして問題ない。取得できなかった場合の保険値として
        // iPhoneでよくある解像度・スケールを使う(取得できないのは通常起こらない想定)。
        let screen = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
        let scale = screen?.scale ?? 3.0
        let bounds = screen?.bounds ?? CGRect(x: 0, y: 0, width: 430, height: 932)
        let targetSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        return await withCheckedContinuation { continuation in
            // highQualityFormat は低画質版→高画質版と2回コールバックが来ることがあるが、
            // MVPでは待たせすぎないよう最初に来たものをそのまま使う(取得できなければ後続で読み飛ばす)。
            final class ResumeBox: @unchecked Sendable {
                var didResume = false
            }
            let box = ResumeBox()
            PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { image, _ in
                guard !box.didResume else { return }
                box.didResume = true
                continuation.resume(returning: image)
            }
        }
    }

    private static func requestPlayerItem(for asset: PHAsset) async -> AVPlayerItem? {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
                continuation.resume(returning: playerItem)
            }
        }
    }

    /// 動画の再生終了・timeout到達・タイマー全体の終了(タスクのキャンセル)のいずれかまで待つ。
    /// timeout が nil の時は「最後まで再生する」設定を意味し、時間による打ち切りはしない
    /// (ただしタイマー全体が終了してタスクがキャンセルされた場合は、そこですぐ処理を戻す)。
    ///
    /// 【なぜ以前の実装(NotificationCenter + 1回だけのタイマーで待つ)から変えたか】
    /// 以前は「動画の再生終了」通知か「timeoutの経過」のどちらかでしか処理が戻らなかったため、
    /// timeoutがnil(最後まで再生する設定)の状態でタイマー全体が終了すると、動画の再生終了を
    /// 待ち続けたまま処理が戻らなくなる(実質のフリーズ)おそれがあった。写真の待ち方
    /// (`try? await Task.sleep`)と同じく、短い間隔で寝ては起きてキャンセルを確認する方式にすることで、
    /// どのケースでも確実に処理が戻るようにしている。
    /// 【指摘E対応: 再生失敗を検知していなかった不具合】
    /// 以前は「最後まで再生する」設定の時、`AVPlayerItemDidPlayToEndTime`(正常に最後まで再生し終えた
    /// 通知)しか見ていなかった。壊れた動画・iCloudから取得できない動画などで再生に失敗した場合は
    /// この通知が一切来ないため、`timeout` が nil(最後まで再生する設定)だと真っ黒な画面のまま
    /// タイマーが終わるまでずっと止まって見えてしまっていた。
    /// 再生失敗は (1) `AVPlayerItemFailedToPlayToEndTime` 通知、(2) `player.currentItem?.status == .failed`
    /// (通知が来る前に状態だけ先に失敗になるケースがあるため、ポーリングでも念のため確認する)
    /// の2通りで検知し、どちらかが起きたら「最後まで再生する」設定でもそこで処理を戻す。
    private static func waitForVideoToFinish(player: AVPlayer, timeout: TimeInterval?) async {
        final class DidFinishBox: @unchecked Sendable {
            var didFinish = false
        }
        let box = DidFinishBox()
        let endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in box.didFinish = true }
        let failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in box.didFinish = true }
        defer {
            NotificationCenter.default.removeObserver(endObserver)
            NotificationCenter.default.removeObserver(failObserver)
        }

        let start = Date()
        while !box.didFinish {
            if Task.isCancelled { return }
            if player.currentItem?.status == .failed { return }
            if let timeout, Date().timeIntervalSince(start) >= timeout { return }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒ごとに確認
        }
    }
}
