import SwiftUI

/// 対戦タブのトップ。CPU対戦を始める入り口。
/// 【2026-09-13仕様変更】デッキ編成機能を廃止したため、「デッキを編成する」の
/// 入り口は無くなった。手札は毎回、持っているカードの中から自動で決まる。
struct BattleHomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                Text("コンピューターと対戦")
                    .font(.title2.bold())
                Text("毎ターン、お題の要素と「高い方/低い方どちらが勝ちか」がランダムに決まります。あなたとCPUのカードは、持っているカードの中から自動で選ばれます。5ターン(同じ要素は出ません)のうち、勝ちが多い方が対戦の勝者です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                NavigationLink("対戦を始める") {
                    BattlePlayView()
                }
                .buttonStyle(.gamePrimary)
                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("対戦")
        }
    }
}
