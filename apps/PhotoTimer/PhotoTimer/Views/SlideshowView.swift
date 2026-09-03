import SwiftUI
import AVKit
import Photos

/// タイマーが動いている間、写真・動画を全画面で流し続ける画面。
struct SlideshowView: View {
    let totalSeconds: Int
    let settings: FilterSettings
    let playbackSettings: PlaybackSettings
    let placeClusters: [PlaceCluster]

    @StateObject private var controller = TimerController()
    @Environment(\.dismiss) private var dismiss

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
                if controller.noCandidatesFound {
                    noResultsView
                } else if controller.phase == .finished {
                    finishedView
                }
            }
            .padding()
        }
        .statusBarHidden()
        .onAppear {
            controller.start(totalDurationSeconds: totalSeconds, settings: settings, playbackSettings: playbackSettings, placeClusters: placeClusters)
        }
        .onDisappear {
            controller.stop()
        }
        .animation(.easeInOut(duration: 0.4), value: controller.currentAsset?.localIdentifier)
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

            Spacer()

            Text(timeString(controller.remainingSeconds))
                .font(.system(.title2, design: .rounded).monospacedDigit().bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.black.opacity(0.4), in: Capsule())
                // 自動テストがカウントダウンの残り秒数を読み取るための目印。
                .accessibilityIdentifier("remainingTimeLabel")
        }
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundStyle(.white)
            Text("条件に合う写真・動画が見つかりませんでした")
                .foregroundStyle(.white)
            Button("閉じる") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 40)
    }

    private var finishedView: some View {
        VStack(spacing: 12) {
            Text("タイマー終了")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Button("閉じる") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 40)
    }

    private func timeString(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
