import SwiftUI

/// 対戦タブのトップ。CPU対戦を始める入り口。
/// 【2026-09-13仕様変更】デッキ編成機能を廃止したため、「デッキを編成する」の
/// 入り口は無くなった。
/// 【2026-09-14仕様変更】手札は自動でランダムに出るのではなく、CPUのカードを
/// 先に見てから、自分の手札4枚の中から選んで出す方式に変更した。
struct BattleHomeView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                EarthBackdrop(variant: .battle)
            VStack(spacing: 24) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                Text("コンピューターと対戦")
                    .font(.title2.bold())
                Text("毎ターン、お題の要素と「高い方/低い方どちらが勝ちか」がランダムに決まります。CPUのカード(国・要素は見える、数値は伏せたまま)が先に提示されるので、それを見てから自分の手札4枚の中から1枚選んで出しましょう。5ターン(同じ要素は出ません)のうち、勝ちが多い方が対戦の勝者です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                NavigationLink("対戦を始める") {
                    BattlePlayView()
                }
                .buttonStyle(EarthActionButtonStyle())
                Spacer()
            }
            .padding(.top, 40)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
