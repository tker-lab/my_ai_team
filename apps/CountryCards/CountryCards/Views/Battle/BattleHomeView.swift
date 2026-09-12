import SwiftUI

/// 対戦タブのトップ。CPU対戦を始める・デッキを編成する、の入り口。
struct BattleHomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                Text("コンピューターと対戦")
                    .font(.title2.bold())
                Text("毎ターン、お題の要素と「高い方/低い方どちらが勝ちか」がランダムに決まります。5ターン中、勝ちが多い方が対戦の勝者です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                NavigationLink("対戦を始める") {
                    BattlePlayView()
                }
                .buttonStyle(.borderedProminent)

                NavigationLink("デッキを編成する") {
                    DeckEditorView()
                }
                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("対戦")
        }
    }
}
