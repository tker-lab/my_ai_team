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
        phase = .idle
        // 動画再生中に閉じられた場合に備え、念のため音声セッションも手放しておく(指摘D関連)。
        Self.deactivateAudioSession()
    }

    private func runCountdown() async {
        while remainingSeconds > 0 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            remainingSeconds -= 1
        }
        finish()
    }

    private func finish() {
        guard phase == .running else { return }
        phase = .finished
        runLoopTask?.cancel()
        currentPlayer?.pause()
        // カウントダウン終了を知らせる(仮:動画の音を止めてアラーム音のみ鳴らす。詳細はCEO確認事項)
        AudioServicesPlaySystemSound(1005)
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
                let reason: NoCandidatesReason = sawAnyCandidateThisPass ? .loadFailed : .noMatchingPhotos
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
            Self.activateAudioSessionForPlayback() // 指摘D: 再生する瞬間だけ音声セッションを確保する
            player.play() // 動画は音付きで再生(MVP必須要件)
            // 「指定秒数で切り上げる」設定の時だけ上限を設ける。「最後まで再生する」設定の時は上限なし(nil)。
            let timeout: TimeInterval? = playbackSettings.videoPlaybackMode == .capped ? playbackSettings.videoCapSeconds : nil
            await Self.waitForVideoToFinish(player: player, timeout: timeout)
            player.pause()
            Self.deactivateAudioSession() // 指摘D: 再生が終わったら手放し、他アプリの音楽を妨げないようにする
            return true
        default:
            guard let image = await Self.requestDisplayImage(for: asset) else { return false }
            if Task.isCancelled { return false }
            currentImage = image
            try? await Task.sleep(nanoseconds: UInt64(playbackSettings.photoSlideDurationSeconds * 1_000_000_000))
            return true
        }
    }

    // MARK: - 音声セッション(指摘D対応)

    /// 動画を再生する瞬間だけ音声セッションを確保する。
    /// 【なぜ「アプリ起動時にまとめて確保」から「再生の瞬間だけ」に変えたか】
    /// 以前は PhotoTimerApp の起動時(init)に確保しっぱなしにしていたため、フィルタ画面を見ているだけ、
    /// あるいはタイマーを設定しているだけでも他アプリ(音楽アプリ等)の再生が強制的に止まってしまう
    /// 不具合があった(指摘D)。動画を再生する瞬間だけ確保することで、写真だけが流れている間や
    /// タイマーを使っていない間は他アプリの音楽を邪魔しない。
    private static func activateAudioSessionForPlayback() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// 動画の再生が終わったら音声セッションを手放す。`.notifyOthersOnDeactivation` を指定することで、
    /// 一時停止していた他アプリの音楽に「再開してよい」ことを伝える(Appleの推奨パターン)。
    private static func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 画像・動画の取得

    private static func requestDisplayImage(for asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true // 本人のiCloud上の写真も表示できるようにする(仮の判断。詳細は報告参照)
        options.resizeMode = .fast

        let targetSize = CGSize(width: UIScreen.main.bounds.width * UIScreen.main.scale,
                                 height: UIScreen.main.bounds.height * UIScreen.main.scale)

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
    private static func waitForVideoToFinish(player: AVPlayer, timeout: TimeInterval?) async {
        final class DidFinishBox: @unchecked Sendable {
            var didFinish = false
        }
        let box = DidFinishBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in box.didFinish = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        let start = Date()
        while !box.didFinish {
            if Task.isCancelled { return }
            if let timeout, Date().timeIntervalSince(start) >= timeout { return }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒ごとに確認
        }
    }
}
