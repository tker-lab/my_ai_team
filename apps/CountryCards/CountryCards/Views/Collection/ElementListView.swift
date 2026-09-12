import SwiftUI

/// 要素別ランキングの入り口一覧(10要素)。
struct ElementListView: View {
    @ObservedObject private var database = CardDatabase.shared
    @ObservedObject private var owned = OwnedCollection.shared

    var body: some View {
        List {
            Section {
                CollectionScopeNoticeView()
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
            ForEach(CardElement.allCases) { element in
                NavigationLink(value: element) {
                    HStack {
                        Circle()
                            .fill(element.borderColor)
                            .frame(width: 14, height: 14)
                        Text(element.displayName)
                        Spacer()
                        let cards = database.cards(forElement: element)
                        let ownedCount = cards.filter(owned.owns).count
                        Text("\(ownedCount)/\(cards.count)枚")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationDestination(for: CardElement.self) { element in
            ElementRankingView(element: element)
        }
    }
}
