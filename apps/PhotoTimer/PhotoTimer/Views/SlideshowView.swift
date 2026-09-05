import SwiftUI
import AVKit
import Photos

/// タイマーが動いている間、写真・動画を全画面で流し続ける画面。
struct SlideshowView: View {
    let totalSeconds: Int
    let settings: FilterSettings
    let playbackSettings: PlaybackSettings
    let alarmSettings: AlarmSettings
    let placeClusters: [PlaceCluster]

    /// 新規開始の時は nil(=今から始める)。前回のタイマーを再開する時だけ、
    /// 前回計算済みの終了予定時刻(絶対時刻)を渡す(RootView参照。CEO要望C)。
    var resumingUntil: Date? = nil

    @StateObject private var controller = TimerController()
    @Environment(\.dismiss) private var dismiss
    /// CEO要望C(2026-09-05):バックグラウンドに回っている間は解析・表示を止め、
    /// 戻ってきたら経過時間を正しく反映して再開する。
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedHistoryIDs: Set<String> = []
    @State private var showingDeleteConfirmation = false
    @State private var isHistoryDeleteMode = false
    @State private var previewItem: HistoryPreviewItem?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = controller.currentImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .id(controller.currentAsset?.localIdentifier)
                    // 自動テストが「表示中の写真が実際に切り替わったか」を判定するための目印。
                    // 値は写真ごとの内部ID(localIdentifier)と表示通し番号(displayToken)を含む文字列で、
                    // 画面表示には影響しない。通し番号は「候補が少なく同じ写真・動画が連続で選ばれた場合」でも
                    // 切り替わりを見分けられるようにするためのもの([[xcuitest-accessibility-id-content-change-detection]]参照)。
                    .accessibilityIdentifier("media-photo-\(controller.displayToken)-\(controller.currentAsset?.localIdentifier ?? "none")")
            } else if let player = controller.currentPlayer {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .id(controller.currentAsset?.localIdentifier)
                    .accessibilityIdentifier("media-video-\(controller.displayToken)-\(controller.currentAsset?.localIdentifier ?? "none")")
            } else if controller.phase == .running {
                ProgressView("読み込み中…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            VStack {
                topBar
                Spacer()
                if let reason = controller.noCandidatesReason {
                    noResultsView(reason: reason)
                } else if controller.phase == .finished {
                    finishedView
                }
            }
            .padding()

            if let previewItem {
                HistoryPreviewView(asset: previewItem.asset) { self.previewItem = nil }
                    .zIndex(10)
            }
        }
        .statusBarHidden()
        .onAppear {
            controller.start(totalDurationSeconds: totalSeconds, settings: settings, playbackSettings: playbackSettings, alarmSettings: alarmSettings, placeClusters: placeClusters, resumingUntil: resumingUntil)
            // 指摘C: スライドショー中は画面の自動ロックを止める(この画面にいる間だけ)。
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            controller.stop()
            // この画面を離れたら元に戻す(スライドショー中以外は通常どおり自動ロックさせる)。
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { _, newPhase in
            // CEO要望C(2026-09-05):バックグラウンドに回ったら解析・表示を止め、
            // 戻ってきたら経過時間を正しく反映して表示を再開する。
            switch newPhase {
            case .background:
                controller.enterBackground()
            case .active:
                controller.returnToForeground()
            case .inactive:
                break // 通知センターを開く等の一時的な状態。ここでは何もしない。
            @unknown default:
                break
            }
        }
        .animation(.easeInOut(duration: 0.4), value: controller.currentAsset?.localIdentifier)
        // CEO要望D(2026-09-05): 削除に失敗した場合だけユーザーに知らせる
        // (キャンセルは正常系なので何も表示しない。TimerController.deleteCurrentAsset()参照)。
        .alert("削除できませんでした", isPresented: deletionFailureAlertBinding) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("時間をおいてもう一度お試しください。")
        }
        // 【高2の回帰テスト修正で発覚した実際の不具合・2026-09-05】
        // 以前はここを.confirmationDialog(...)にしていた。テストのクエリ自体を直したところ
        // (元々のバグ:app.otherElements["sessionHistoryGrid"]がScrollViewと一致せず、
        // このダイアログの確認自体が一度も実行されていなかった)、このアプリが動作するiOS
        // (26系)では.confirmationDialogに「削除」(destructive)と「キャンセル」(cancel)の
        // 2つのボタンを渡すと、「キャンセル」だけが画面にもアクセシビリティツリーにも
        // 一切現れない(タップする手段が無い)という実際の不具合が見つかった
        // (finishedViewから画面全体のZStackへ付け替えても症状は変わらず、位置や大きさの
        // 問題ではないと切り分けた)。単純な「1つの破壊的操作+キャンセル」という組み合わせは
        // 本来.alertが想定する形そのものであり、削除失敗時の通知(上のdeletionFailureAlertBinding)
        // も既に.alertで正しく動いていたため、こちらも.alertに変更したところ両方のボタンが
        // 正しく表示・タップできるようになった(自動テストで確認済み。完了報告に実行ログを記載)。
        .alert("選択した\(selectedHistoryIDs.count)件を削除しますか？", isPresented: $showingDeleteConfirmation) {
            Button("削除", role: .destructive) {
                let assets = controller.displayedAssets.filter { selectedHistoryIDs.contains($0.localIdentifier) }
                selectedHistoryIDs.removeAll()
                controller.deleteAssets(assets)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("次に表示されるiPhone標準の確認画面でも削除を確定する必要があります。")
        }
    }

    private var deletionFailureAlertBinding: Binding<Bool> {
        Binding(
            get: { controller.deletionFailure != nil },
            set: { if !$0 { controller.clearDeletionFailure() } }
        )
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, .black.opacity(0.4))
            }
            // 自動テスト(XCUITest)がこの✕ボタンを確実に見つけられるようにするための目印。
            // 画面表示や動作には影響しない。
            .accessibilityIdentifier("closeButton")

            Spacer()

            Text(timeString(controller.remainingSeconds))
                .font(.system(.title2, design: .rounded).monospacedDigit().bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.black.opacity(0.4), in: Capsule())
                // 自動テストがカウントダウンの残り秒数を読み取るための目印。
                .accessibilityIdentifier("remainingTimeLabel")

            Spacer()

            Color.clear.frame(width: 28, height: 28)
        }
    }

    /// 指摘I対応: 「条件に合う写真が無い」のか「合う写真はあるが読み込みに失敗した」のかで
    /// メッセージを変える(原因が分かった方がユーザーが次に何をすべきか判断しやすいため)。
    private func noResultsView(reason: TimerController.NoCandidatesReason) -> some View {
        VStack(spacing: 12) {
            Image(systemName: reason == .loadFailed ? "icloud.slash" : "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundStyle(.white)
            Text(message(for: reason))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button("閉じる") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 40)
    }

    private func message(for reason: TimerController.NoCandidatesReason) -> String {
        switch reason {
        case .noMatchingPhotos:
            return "条件に合う写真・動画が見つかりませんでした"
        case .loadFailed:
            // 指摘H対応: 原因は「iCloud上にしか無い写真」だけでなく、「iPhoneのストレージを最適化」設定で
            // 端末内から写真の実データが取り除かれているケースもあるため、両方が伝わる文言にする。
            return "写真・動画を読み込めませんでした\n(iCloud上にしか無い、または「ストレージを最適化」で端末内に無い写真の可能性があります。電波の良い場所でお試しください)"
        }
    }

    /// タイマー終了時の画面。CEO要望(2026-09-05):アラームの鳴らし方に「止めるまで鳴り続ける」
    /// パターンを追加したため、まず音(・バイブレーション)だけを止めるボタンを用意し、
    /// 止まったら「閉じる」に切り替わる、という2段階にした
    /// (iPhone標準のアラームと同じく「音を止める」と「画面を閉じる」を分けている。
    /// n回鳴って終わるパターンで自然に鳴り終わった場合も、controller.isAlarmSoundingが自動で
    /// falseになるため、ボタンは操作しなくても自動的に「閉じる」に切り替わる)。
    private var finishedView: some View {
        VStack(spacing: 12) {
            Text("タイマー終了")
                .font(.title2.bold())
                .foregroundStyle(.white)
            if controller.isAlarmSounding {
                Button("アラームを止める") {
                    controller.stopAlarm()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityIdentifier("stopAlarmButton")
            } else {
                if FeatureFlags.isSessionHistoryEnabled, !controller.displayedAssets.isEmpty {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                            ForEach(controller.displayedAssets, id: \.localIdentifier) { asset in
                                Button {
                                    if isHistoryDeleteMode { toggleHistorySelection(asset.localIdentifier) }
                                    else { previewItem = HistoryPreviewItem(asset: asset) }
                                } label: {
                                    HistoryThumbnail(asset: asset, selected: isHistoryDeleteMode && selectedHistoryIDs.contains(asset.localIdentifier))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 360)
                    .accessibilityIdentifier("sessionHistoryGrid")
                    if FeatureFlags.isHistoryDeletionEnabled {
                        if isHistoryDeleteMode {
                            HStack {
                                Button("削除モード終了") {
                                    isHistoryDeleteMode = false
                                    selectedHistoryIDs.removeAll()
                                }
                                Spacer()
                                Button("全選択") {
                                    selectedHistoryIDs = Set(controller.displayedAssets.map(\.localIdentifier))
                                }
                                .disabled(selectedHistoryIDs.count == controller.displayedAssets.count)
                                Button("全解除") { selectedHistoryIDs.removeAll() }
                                    .disabled(selectedHistoryIDs.isEmpty)
                            }
                            if !selectedHistoryIDs.isEmpty {
                                Button("選択した項目を削除(\(selectedHistoryIDs.count))", role: .destructive) {
                                    showingDeleteConfirmation = true
                                }
                                .accessibilityIdentifier("deleteSelectedHistoryButton")
                            }
                        } else {
                            Button("削除する項目を選ぶ") {
                                isHistoryDeleteMode = true
                                selectedHistoryIDs.removeAll()
                            }
                            .accessibilityIdentifier("enterHistoryDeleteModeButton")
                        }
                    }
                }
                Button("閉じる") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("finishedCloseButton")
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 40)
    }

    private func toggleHistorySelection(_ id: String) {
        if selectedHistoryIDs.contains(id) { selectedHistoryIDs.remove(id) }
        else { selectedHistoryIDs.insert(id) }
    }

    private func timeString(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

private struct HistoryPreviewItem: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

private struct HistoryPreviewView: View {
    let asset: PHAsset
    let close: () -> Void
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    /// 【中5対応】取得できなかった(iCloud上のみ・取得失敗)場合にtrueにする。
    /// これが無いと、image・playerがどちらもnilのまま「読み込み中」と見分けが付かず、
    /// ProgressViewが無言で回り続けてしまっていた。
    @State private var loadFailed = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let player { VideoPlayer(player: player).ignoresSafeArea() }
            else if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if loadFailed {
                // スライドショー本体(TimerController)のloadFailed文言と揃える。
                Text("写真・動画を読み込めませんでした\n(iCloud上にしか無い、または「ストレージを最適化」で端末内に無い写真の可能性があります。電波の良い場所でお試しください)")
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            else { ProgressView().tint(.white) }
            Button { close() } label: {
                Image(systemName: "chevron.backward.circle.fill").font(.largeTitle).foregroundStyle(.white, .black.opacity(0.4))
            }
            .padding()
            .accessibilityIdentifier("closeHistoryPreviewButton")
        }
        .task {
            if asset.mediaType == .video {
                let options = PHVideoRequestOptions(); options.isNetworkAccessAllowed = true
                let item = await withCheckedContinuation { continuation in
                    PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                        continuation.resume(returning: item)
                    }
                }
                if let item {
                    player = AVPlayer(playerItem: item)
                    player?.play()
                } else {
                    loadFailed = true
                }
            } else {
                let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = true; options.deliveryMode = .highQualityFormat
                image = await Self.requestFullQualityImage(for: asset, options: options)
                if image == nil { loadFailed = true }
            }
        }
        .onDisappear { player?.pause() }
    }

    /// 【中6対応】highQualityFormatは「まず低画質の仮画像→続いて高画質の本画像」と
    /// 2回コールバックが来ることがある(TimerController.requestDisplayImageと同じ理由)。
    /// 以前はここに二重完了の防御が無く(継続を2回resumeするとクラッシュしうる)、かつ
    /// 「低画質の仮画像だけが来て、その後の本画像がついに来ない」失敗時に、最終判定
    /// (degraded以外)を待ち続けて永久にresumeされない可能性もあった。
    /// ①最終画質(degradedでない)が来た、②取得自体に失敗しimageがnilで来た、のどちらか
    /// 早い方で必ず1回だけ確定させることで、両方の不具合を同時に塞ぐ。
    private static func requestFullQualityImage(for asset: PHAsset, options: PHImageRequestOptions) async -> UIImage? {
        await withCheckedContinuation { continuation in
            final class ResumeBox: @unchecked Sendable { var didResume = false }
            let box = ResumeBox()
            PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) { image, info in
                guard !box.didResume else { return }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                // 仮画像(degraded)がまだ来ただけで、imageも取れている場合だけ本画像を待つ。
                // それ以外(最終画質が来た/imageがnilで失敗した)は、ここで確定させる。
                guard !degraded || image == nil else { return }
                box.didResume = true
                continuation.resume(returning: image)
            }
        }
    }
}

private struct HistoryThumbnail: View {
    let asset: PHAsset
    let selected: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else { Color.gray.opacity(0.35).overlay { ProgressView() } }
            }
            .frame(height: 90).clipped()
            if asset.mediaType == .video {
                Image(systemName: "video.fill").padding(5).foregroundStyle(.white)
            }
            if selected {
                Image(systemName: "checkmark.circle.fill").padding(5).foregroundStyle(.blue).background(.white, in: Circle())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).stroke(selected ? Color.blue : .clear, lineWidth: 3) }
        .task(id: asset.localIdentifier) { image = await Self.thumbnail(for: asset) }
    }

    /// 【中6対応】以前はローカル変数(var completed)をエスケープするクロージャの中で直接
    /// 書き換えていたが、他所(TimerController.requestDisplayImage・
    /// HistoryPreviewView.requestFullQualityImage)と同じ「小さなBoxクラス」の形に揃えた
    /// (書き方の統一。加えて、degraded=trueの仮画像だけが来て終わる失敗ケースでも
    /// 待ち続けずに済むよう、image==nilの時は即確定させるようにした)。
    private static func thumbnail(for asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        return await withCheckedContinuation { continuation in
            final class ResumeBox: @unchecked Sendable { var didResume = false }
            let box = ResumeBox()
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 240, height: 240), contentMode: .aspectFill, options: options) { image, info in
                guard !box.didResume else { return }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) == true
                guard !degraded || image == nil else { return }
                box.didResume = true
                continuation.resume(returning: image)
            }
        }
    }
}
