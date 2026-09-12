import SwiftUI
import UIKit

/// iOS標準の共有シート(UIActivityViewController)をSwiftUIから使うためのラッパー。
///
/// なぜX(Twitter)専用のボタンにしなかったか(CEOからの申し送り事項):
/// X専用のAPI連携は別途アプリ登録・審査が必要になる上、Xでしかシェアできない。
/// iOS標準の共有シートなら、LINE・Instagram・メモ・メールなど端末に入っている
/// どのアプリにもシェアでき、実装の手間も増えない。
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// カード1枚を画像化してシェアするボタン。ガチャ結果画面・コレクション画面の
/// 両方から共通で使う(CEO決定:カード画像+レア度+要素名+数値をシェア対象にする)。
struct CardShareButton: View {
    let card: Card
    let country: Country?

    @State private var shareItems: [Any]?

    var body: some View {
        Button {
            shareItems = makeShareItems()
        } label: {
            Label("シェア", systemImage: "square.and.arrow.up")
        }
        .sheet(isPresented: Binding(
            get: { shareItems != nil },
            set: { if !$0 { shareItems = nil } }
        )) {
            if let shareItems {
                ShareSheet(activityItems: shareItems)
            }
        }
    }

    /// カードの見た目(CardView)をそのまま画像化する。SwiftUIのビューを画像に
    /// 変換できるImageRenderer(iOS16以降)を使うことで、カードのデザインを
    /// 二重に実装せずに済む(見た目はCardViewが唯一の正=1箇所直せば両方直る)。
    @MainActor
    private func makeShareItems() -> [Any] {
        let renderer = ImageRenderer(content:
            CardView(card: card, country: country)
                .frame(width: 160, height: 220)
        )
        renderer.scale = UIScreen.main.scale
        let countryName = country?.nameJa ?? card.iso3
        let caption = "国カードバトルで\(countryName)の「\(card.element.displayName)」カード"
            + "(\(card.rarity.displayName))をゲット!"

        if let uiImage = renderer.uiImage {
            return [caption, uiImage]
        }
        return [caption]
    }
}
