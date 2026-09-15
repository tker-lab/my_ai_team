import SwiftUI

/// ¥100の10連ガチャの要素選択一覧。
struct IAPGachaElementListView: View {
    var body: some View {
        NavigationStack {
            ZStack { EarthBackdrop(variant: .gacha(.ur)); ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 12) { ForEach(CardElement.allCases) { element in NavigationLink(value: element) { ElementSigilButton(element: element, detail: "30枚・SSR以上保証") }.buttonStyle(.plain) } }.padding() } }
            .earthNavigationTitle("¥100で10連")
            .navigationDestination(for: CardElement.self) { element in
                IAPGachaView(element: element)
            }
        }
    }
}
