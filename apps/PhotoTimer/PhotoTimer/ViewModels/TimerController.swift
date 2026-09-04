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
@MainActor
final class TimerController: ObservableObject {
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

    /// 写真1枚あたりの表示秒数・動画の再生時間の扱い。CEO要望(2026-09-04)によりユーザー設定可能。
    /// `start(...)` の呼び出し時に渡された値をここに保持する(既定値は元の固定値と同じ)。
    private var playbackSettings: PlaybackSettings = .default

    private var engine: CandidateEngine?
    private var runLoopTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?

    func start(totalDurationSeconds: Int, settings: FilterSettings, playbackSettings: PlaybackSettings, placeClusters: [PlaceCluster]) {
        stop()

        phase = .running
        noCandidatesReason = nil
        totalSeconds = totalDurationSeconds
        remainingSeconds = totalDurationSeconds
        self.playbackSettings = playbackSettings

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
        currentAsset = nil
        // 軽微指摘対応: 次回 start() まで前回の CandidateEngine を握ったままにしないよう nil に戻す
        // (機能上の実害は無いが、使い終わった実体を持ち続けない、という後始末を明確にする)。
        engine = nil
        phase = .idle
        // 動画再生中に閉じられた場合に備え、念のため音声セッションも手放しておく(指摘D関連)。
        deactivateAudioSessionIfNeeded()
    }

    /// 【軽微指摘対応: カウントダウンが実時間からズレていく不具合】
    /// 以前は「1秒スリープして1引く」を繰り返すだけだったため、スリープ自体のわずかなオーバーヘッド
    /// (OSのスケジューリングの都合など)が毎回積み重なり、タイマーが長いほど実際の経過時間より
    /// 表示上の残り時間の減りが遅くなっていく(実時間とズレる)不具合があった。
    /// 今は「開始時刻から数えて本来あと何秒か」を毎回時計(Date)から計算し直すことで、
    /// 1回ごとのズレが蓄積しないようにしている。
    private func runCountdown() async {
        let deadline = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        while remainingSeconds > 0 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            remainingSeconds = max(0, Int(deadline.timeIntervalSinceNow.rounded()))
        }
        finish()
    }

    private func finish() {
        guard phase == .running else { return }
        phase = .finished
        runLoopTask?.cancel()
        currentPlayer?.pause()
        // カウントダウン終了を知らせる(仮:動画の音を止めてアラーム音のみ鳴らす。詳細はCEO確認事項)
        //
        // 【実機確認事項への対応: マナーモード(消音スイッチ)でアラームが聞こえない問題】
        // `AudioServicesPlaySystemSound` は、その時点でアプリの音声セッションが「消音スイッチの
        // 影響を受けないカテゴリ(.playback等)」になっていない限り、消音スイッチがオンだと
        // 無音になる(Appleの仕様。QA1631)。このアプリは直前まで写真だけが表示されていると
        // 音声セッションを手放している状態(指摘D対応)のため、そのままだとタイマーが鳴っても
        // マナーモード中は本当に何も聞こえない可能性があった(タイマーアプリとして致命的)。
        // アラームを鳴らす直前に音声セッションを.playbackへ切り替えることで、消音スイッチの
        // 状態によらず必ず音が鳴るようにする。
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        AudioServicesPlaySystemSound(1005)
        // 万一(機種・設定・音量0などで)音に気づけない場合の保険として、バイブレーションも併用する
        // (指摘: バイブレーションの併用が無かった)。
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
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

            while phase == .running, !Task.isCancelled {
                guard let asset = await engine.next() else { break } // このシャッフル分は全部試し終えた
                sawAnyCandidateThisPass = true
                if Task.isCancelled { break }
                currentAsset = asset
                displayToken += 1
                let displayed = await displayAndWait(asset: asset)
                if displayed { displayedAnyThisPass = true }
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

    /// 1枚(1本)を表示し、表示時間だけ待つ。実際に表示できた場合は true、
    /// 読み込みに失敗して何も表示できなかった場合は false を返す(指摘B・I対応)。
    @discardableResult
    private func displayAndWait(asset: PHAsset) async -> Bool {
        currentPlayer?.pause()
        currentPlayer = nil
        currentImage = nil

        switch asset.mediaType {
        case .video:
            guard let playerItem = await Self.requestPlayerItem(for: asset) else { return false }
            if Task.isCancelled { return false }
            let player = AVPlayer(playerItem: playerItem)
            currentPlayer = player
            activateAudioSessionIfNeeded() // 指摘D: 再生する瞬間だけ音声セッションを確保する
            player.play() // 動画は音付きで再生(MVP必須要件)
            // 「指定秒数で切り上げる」設定の時だけ上限を設ける。「最後まで再生する」設定の時は上限なし(nil)。
            let timeout: TimeInterval? = playbackSettings.videoPlaybackMode == .capped ? playbackSettings.videoCapSeconds : nil
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
            try? await Task.sleep(nanoseconds: UInt64(playbackSettings.photoSlideDurationSeconds * 1_000_000_000))
            return true
        }
    }

    // MARK: - 音声セッション(指摘D対応 + 軽微指摘対応)

    /// 今、音声セッション(動画の音を鳴らすための権利のようなもの)を確保している最中かどうか。
    /// これを見て「すでに確保済みなら何もしない/まだ確保していなければ確保する」を判断することで、
    /// 動画が連続する時に毎回 確保→解放 を繰り返さないようにする。
    private var isAudioSessionActive = false

    /// 動画を再生する瞬間だけ音声セッションを確保する。すでに確保済みなら何もしない
    /// (動画が連続する時に、動画ごとに確保し直して他アプリの音楽を毎回止めてしまうのを防ぐ)。
    /// 【なぜ「アプリ起動時にまとめて確保」から「再生の瞬間だけ」に変えたか】
    /// 以前は PhotoTimerApp の起動時(init)に確保しっぱなしにしていたため、フィルタ画面を見ているだけ、
    /// あるいはタイマーを設定しているだけでも他アプリ(音楽アプリ等)の再生が強制的に止まってしまう
    /// 不具合があった(指摘D)。動画を再生する瞬間だけ確保することで、写真だけが流れている間や
    /// タイマーを使っていない間は他アプリの音楽を邪魔しない。
    private func activateAudioSessionIfNeeded() {
        guard !isAudioSessionActive else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
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
