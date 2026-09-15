import SwiftUI

/// プロフィール画面。ユーザー名の登録、実績の王冠、累計記録(対戦勝利数・
/// ガチャ使用回数)を表示する(決定事項どおり)。
struct ProfileView: View {
    @ObservedObject private var owned = OwnedCollection.shared
    @ObservedObject private var database = CardDatabase.shared
    @State private var isEditingName = false
    @State private var nameDraft = ""

    private var tier: CrownTier {
        CrownTier.current(
            uniqueOwnedCount: owned.uniqueCardCount,
            totalCardCount: database.totalCardCountIncludingSpecial
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                EarthBackdrop(variant: .profile)
                ScrollView { VStack(spacing: 16) {
                    EarthTopBar(title: "遠征記録") { EmptyView() }
                    ArchivePanel(variant: .hero) {
                    HStack(spacing: 14) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(
                                LinearGradient(colors: [tier.color, tier.color.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                            )
                            .shadow(color: tier.color.opacity(0.5), radius: 6)
                            .accessibilityIdentifier("profileCrown")

                        VStack(alignment: .leading) {
                            Text(owned.username ?? "名前未登録")
                                .font(.title3.bold())
                            // 【2026-09-13修正】Text内で数値をそのまま埋め込むと、iOSが
                            // 自動でカンマ区切り(例:1,886)を付けてしまう。String(...)で
                            // 明示的に文字列化することでカンマを付けないようにする
                            // (数値表示をカンマ区切りにしない、という決定事項に統一)。
                            Text("集めたカード \(String(owned.uniqueCardCount)) / \(String(database.totalCardCountIncludingSpecial))枚")
                                .font(.caption)
                                .foregroundStyle(EarthColors.secondary)
                        }
                        Spacer()
                        Button("編集") {
                            nameDraft = owned.username ?? ""
                            isEditingName = true
                        }
                        .buttonStyle(EarthActionButtonStyle(variant: .quiet))
                    }
                    .padding(.vertical, 6)
                }

                ArchivePanel { VStack(spacing: 14) {
                    recordRow("対戦の累計勝利数", "\(owned.battleWinCount)勝")
                    recordRow("ガチャの累計使用回数", "\(owned.gachaUseCount)回")
                    recordRow("ダブりポイント", "\(owned.dupePoints)pt")
                } }

                NavigationLink { LeaderboardView() } label: { Label("全国ランキングを見る", systemImage: "chart.bar.fill") }.buttonStyle(EarthActionButtonStyle(variant: .secondary))
                ArchivePanel { VStack(alignment: .leading, spacing: 8) {
                    Text("王冠について").font(.headline)
                    Text("持っているカードの種類数に応じて王冠が10段階で変化し、完全収集で金色になります。").font(.caption).foregroundStyle(EarthColors.secondary)
                } }
                NavigationLink { AboutView() } label: { Label("アプリとデータ出典", systemImage: "info.circle.fill") }.buttonStyle(EarthActionButtonStyle(variant: .quiet))
                }.padding(.horizontal, 16) }
                }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isEditingName) {
                SheetWithAdDock { GameModalShell("ユーザー名を登録") {
                    TextField("名前(\(OwnedCollection.usernameMaxLength)文字まで)", text: $nameDraft)
                        .padding(14).background(EarthColors.panel, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(EarthColors.cyan))
                    Text("\(OwnedCollection.usernameMaxLength)文字を超えた分は保存されません。").font(.caption).foregroundStyle(EarthColors.secondary)
                    Button("保存") { owned.updateUsername(nameDraft); isEditingName = false }.buttonStyle(EarthActionButtonStyle())
                }.padding() }
            }
        }
    }

    private func recordRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(EarthColors.secondary); Spacer(); Text(value).fontWeight(.black).monospacedDigit() }
    }
}
