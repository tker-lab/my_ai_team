import SwiftUI

/// 起動画面(タイトル画面)。
///
/// 【2026-09-13追加】チェック工程・CEOの実機確認で「起動していきなりコレクション
/// 画面(タブ)になるのに違和感がある」と指摘された対応。一般的なアプリのように、
/// まずタイトル画面を見せ、タップしてからホーム画面(タブ)に進む流れにする。
/// 名前入力(OnboardingNameView)とは役割が違う:こちらは「アプリの顔」を
/// 見せる導入、名前入力は「初回だけ」出るセットアップ画面。タイトル画面は
/// 毎回の起動時に必ず一度表示する(状態を保存しない)。
struct TitleScreenView: View {
    /// タップされたら呼ばれる(呼び出し側でホーム画面への遷移を行う)。
    var onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOrbiting = false
    @State private var isConverging = false

    var body: some View {
        ZStack {
            EarthBackdrop(variant: .home)
            Circle().stroke(EarthColors.cyan.opacity(0.22), lineWidth: 1).frame(width: 310, height: 110).rotationEffect(.degrees(isOrbiting ? 360 : 0)).offset(y: -120)

            VStack(spacing: 20) {
                Spacer()

                EarthEmblem(size: 132)
                    .shadow(color: EarthColors.cyan.opacity(isOrbiting ? 0.72 : 0.38), radius: isOrbiting ? 28 : 14)

                Text("Country Cards Collection")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(EarthColors.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("カンコレ 〜世界を集めるカードバトル〜")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(EarthColors.secondary)

                Spacer()

                Button("地球図鑑を開く", action: proceed)
                    .buttonStyle(EarthActionButtonStyle()).padding(.horizontal, 36).padding(.bottom, 56)
                    .accessibilityLabel("地球図鑑を開く")
                    .accessibilityHint("ホーム画面へ進みます")
                    .accessibilityIdentifier("titleScreenTapArea")
            }
            .scaleEffect(isConverging ? 0.94 : 1)
            .opacity(isConverging ? 0 : 1)
        }
        .contentShape(Rectangle()).onTapGesture(perform: proceed)
        .accessibilityAction(named: "はじめる", proceed)
        .onAppear {
            guard !reduceMotion else { return }
            Task { try? await Task.sleep(for: .seconds(1.8)); withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) { isOrbiting = true } }
        }
    }

    private func proceed() {
        guard !isConverging else { return }
        withAnimation(.easeIn(duration: 0.22)) { isConverging = true }
        Task { try? await Task.sleep(for: .seconds(reduceMotion ? 0.01 : 0.38)); onTap() }
    }
}

#Preview {
    TitleScreenView(onTap: {})
}
