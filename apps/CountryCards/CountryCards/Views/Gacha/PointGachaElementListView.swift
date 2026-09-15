import SwiftUI

/// ポイントガチャの要素選択一覧。通常ガチャと同様、要素ごとに入り口を分ける。
struct PointGachaElementListView: View {
    var body: some View {
        NavigationStack {
            ZStack { EarthBackdrop(variant: .gacha(.ssr)); ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 12) { ForEach(CardElement.allCases) { element in NavigationLink(value: element) { ElementSigilButton(element: element, detail: "未所持優先") }.buttonStyle(.plain).accessibilityIdentifier("pointElement_\(element.rawValue)") } }.padding() } }
            .earthNavigationTitle("ポイントで引く")
            .navigationDestination(for: CardElement.self) { element in
                PointGachaView(element: element)
            }
        }
    }
}
