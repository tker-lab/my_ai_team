import SwiftUI

/// ポイントガチャの要素選択一覧。通常ガチャと同様、要素ごとに入り口を分ける。
struct PointGachaElementListView: View {
    var body: some View {
        NavigationStack {
            List(CardElement.allCases) { element in
                NavigationLink(element.displayName, value: element)
            }
            .navigationTitle("ポイントで引く")
            .navigationDestination(for: CardElement.self) { element in
                PointGachaView(element: element)
            }
        }
    }
}
