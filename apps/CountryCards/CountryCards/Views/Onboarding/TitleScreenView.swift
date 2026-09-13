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

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.12, blue: 0.30), Color(red: 0.15, green: 0.05, blue: 0.35)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "globe.asia.australia.fill")
                    .font(.system(size: 84))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: .orange.opacity(0.5), radius: isPulsing ? 24 : 10)

                Text("Country Cards Collection")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("カンコレ 〜世界を集めるカードバトル〜")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))

                Spacer()

                Text("タップしてはじめる")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(.white.opacity(isPulsing ? 0.28 : 0.16), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                    .padding(.bottom, 56)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("titleScreenTapArea")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

#Preview {
    TitleScreenView(onTap: {})
}
