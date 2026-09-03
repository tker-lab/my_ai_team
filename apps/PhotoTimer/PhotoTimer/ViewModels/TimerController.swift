import Foundation
import Photos
import AVKit
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

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var totalSeconds: Int = 0
    @Published private(set) var currentAsset: PHAsset?
    @Published private(set) var currentImage: UIImage?
    @Published private(set) var currentPlayer: AVPlayer?
    /// 絞り込み条件に合う写真・動画が1枚も見つからなかった場合に true。
    @Published private(set) var noCandidatesFound = false
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
        noCandidatesFound = false
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

    private func runSlideLoop(engine: CandidateEngine) async {
        await engine.prepare()
        if await engine.candidatePoolCount == 0 {
            noCandidatesFound = true
            phase = .finished
            countdownTask?.cancel()
            return
        }

        while phase == .running, !Task.isCancelled {
            guard let asset = await engine.next() else {
                // シャッフル済みの候補を使い切った。最初から選び直して続ける(ランダム再生をループさせる)。
                await engine.prepare()
                continue
            }
            if Task.isCancelled { break }
            currentAsset = asset
            displayToken += 1
            await displayAndWait(asset: asset)
        }
    }

    private func displayAndWait(asset: PHAsset) async {
        currentPlayer?.pause()
        currentPlayer = nil
        currentImage = nil

        switch asset.mediaType {
        case .video:
            guard let playerItem = await Self.requestPlayerItem(for: asset) else { return }
            if Task.isCancelled { return }
            let player = AVPlayer(playerItem: playerItem)
            currentPlayer = player
            player.play() // 動画は音付きで再生(MVP必須要件)
            // 「指定秒数で切り上げる」設定の時だけ上限を設ける。「最後まで再生する」設定の時は上限なし(nil)。
            let timeout: TimeInterval? = playbackSettings.videoPlaybackMode == .capped ? playbackSettings.videoCapSeconds : nil
            await Self.waitForVideoToFinish(player: player, timeout: timeout)
            player.pause()
        default:
            guard let image = await Self.requestDisplayImage(for: asset) else { return }
            if Task.isCancelled { return }
            currentImage = image
            try? await Task.sleep(nanoseconds: UInt64(playbackSettings.photoSlideDurationSeconds * 1_000_000_000))
        }
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
