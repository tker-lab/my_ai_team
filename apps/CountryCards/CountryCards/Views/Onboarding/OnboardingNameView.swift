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
        ZStack { EarthBackdrop(variant: .home); ScrollView {
            VStack(spacing: 20) {
                EarthEmblem(size: 88).shadow(color: EarthColors.cyan.opacity(0.6), radius: 20).padding(.top, 28)
                Text("探査記録を作成").font(.title2.bold())
                Text("ランキングに表示する名前を決めてください")
                    .font(.subheadline).foregroundStyle(EarthColors.secondary).multilineTextAlignment(.center)
                ArchivePanel(variant: .hero) { VStack(alignment: .leading, spacing: 10) {
                    TextField("観測者名", text: $name).font(.title3.weight(.bold)).padding(16)
                        .background(EarthColors.ink, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(EarthColors.cyan.opacity(0.7)))
                        .onChange(of: name) { _, newValue in if newValue.count > OwnedCollection.usernameMaxLength { name = String(newValue.prefix(OwnedCollection.usernameMaxLength)) } }
                        .accessibilityIdentifier("onboardingNameField")
                    HStack { Text(trimmedName.isEmpty ? "1文字以上入力してください" : "入力済み").foregroundStyle(trimmedName.isEmpty ? EarthColors.coral : EarthColors.cyan); Spacer(); Text("\(name.count)/\(OwnedCollection.usernameMaxLength)").monospacedDigit() }.font(.caption)
                } }
            }.padding(.horizontal, 20).padding(.bottom, 120)
        } }
        .safeAreaInset(edge: .bottom) {
            Button("世界の記録をはじめる") { owned.updateUsername(trimmedName) }
                .buttonStyle(EarthActionButtonStyle()).disabled(trimmedName.isEmpty)
                .accessibilityHint(trimmedName.isEmpty ? "観測者名を入力すると有効になります" : "登録してホームへ進みます")
                .accessibilityIdentifier("onboardingStartButton").padding(.horizontal, 20).padding(.vertical, 10).background(EarthColors.abyss.opacity(0.96))
        }
        .interactiveDismissDisabled() // 名前を決めるまでは閉じられないようにする
    }
}
