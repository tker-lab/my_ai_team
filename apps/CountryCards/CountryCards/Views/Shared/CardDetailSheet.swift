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
                    .padding(.top, 32)

                if let value = card.value {
                    Text("元の数値: \(value, specifier: "%.2f") \(card.element.unit)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
