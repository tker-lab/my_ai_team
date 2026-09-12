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
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(tier.color)
                            .accessibilityIdentifier("profileCrown")

                        VStack(alignment: .leading) {
                            Text(owned.username ?? "名前未登録")
                                .font(.title3.bold())
                            Text("集めたカード \(owned.uniqueCardCount) / \(database.totalCardCountIncludingSpecial)枚")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("編集") {
                            nameDraft = owned.username ?? ""
                            isEditingName = true
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("累計記録") {
                    LabeledContent("対戦の累計勝利数", value: "\(owned.battleWinCount)勝")
                    LabeledContent("ガチャの累計使用回数", value: "\(owned.gachaUseCount)回")
                    LabeledContent("ダブりポイント", value: "\(owned.dupePoints)pt")
                }

                Section("王冠について") {
                    Text("持っているカードの種類数(ダブりを除く)に応じて、王冠の色が10段階で変わります。すべて集めると金色になります。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("プロフィール")
            .alert("ユーザー名を登録", isPresented: $isEditingName) {
                TextField("名前", text: $nameDraft)
                Button("保存") { owned.updateUsername(nameDraft) }
                Button("キャンセル", role: .cancel) {}
            }
        }
    }
}
