import SwiftUI

/// カード1枚をアップで見るシート。図鑑からタップした時にも、ガチャ結果画面
/// からも共通で使う。シェアボタンをここに置く(コレクション画面側の導線)。
struct CardDetailSheet: View {
    let card: Card
    let country: Country?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                CardView(card: card, country: country)
                    .scaleEffect(1.3)
                    // 【2026-09-14修正】scaleEffectは見た目だけを拡大し、
                    // レイアウト上のサイズ(160x220)はそのままなので、
                    // 拡大後の実際の見た目がこの下のテキストと重なっていた
                    // (図鑑バグ再発)。frameで拡大後のサイズを明示的に確保し、
                    // 以降のVStackのspacingが正しい見た目の端から測られるようにする。
                    .frame(width: 160 * 1.3, height: 220 * 1.3)
                    .padding(.top, 32)

                Text("スコア: \(card.score, specifier: "%.1f")点(0〜100点)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                CardShareButton(card: card, country: country)
                    .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
