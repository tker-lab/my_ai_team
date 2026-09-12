import SwiftUI

/// ¥100の10連ガチャの要素選択一覧。
struct IAPGachaElementListView: View {
    var body: some View {
        NavigationStack {
            List(CardElement.allCases) { element in
                NavigationLink(element.displayName, value: element)
            }
            .navigationTitle("¥100で10連")
            .navigationDestination(for: CardElement.self) { element in
                IAPGachaView(element: element)
            }
        }
    }
}
