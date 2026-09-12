import SwiftUI

/// 初回起動時に必ず出す、ユーザー名登録画面。
///
/// チェック工程指摘(2026-09-13):決定事項では「ゲーム開始時に名前を決めて
/// 登録する」だったが、実装がプロフィール画面から後で任意に行う形になって
/// いた。これを直すため、ユーザー名が未登録の間はこの画面がRootTabViewを
/// 覆う形(.fullScreenCover)で必ず表示され、名前を決めるまで先に進めない。
struct OnboardingNameView: View {
    @ObservedObject private var owned = OwnedCollection.shared
    @State private var name = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "flag.2.crossed.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            Text("国カードバトルへようこそ")
                .font(.title2.bold())
            Text("プレイヤー名を決めてください")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("名前(\(OwnedCollection.usernameMaxLength)文字まで)", text: $name)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 40)
                .onChange(of: name) { _, newValue in
                    if newValue.count > OwnedCollection.usernameMaxLength {
                        name = String(newValue.prefix(OwnedCollection.usernameMaxLength))
                    }
                }
                .accessibilityIdentifier("onboardingNameField")

            Button("はじめる") {
                owned.updateUsername(trimmedName)
            }
            .buttonStyle(.borderedProminent)
            .disabled(trimmedName.isEmpty)
            .accessibilityIdentifier("onboardingStartButton")

            Spacer()
            Spacer()
        }
        .padding()
        .interactiveDismissDisabled() // 名前を決めるまでは閉じられないようにする
    }
}
