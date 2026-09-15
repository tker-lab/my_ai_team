import SwiftUI

/// 要素別ランキングの入り口一覧(10要素)。
struct ElementListView: View {
    @ObservedObject private var database = CardDatabase.shared
    @ObservedObject private var owned = OwnedCollection.shared

    var body: some View {
        ScrollView { LazyVStack(spacing: 10) {
            CollectionScopeNoticeView()
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
                        Text("\(String(ownedCount))/\(String(cards.count))枚")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(element.borderColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(element.borderColor.opacity(0.5)))
                }
                .buttonStyle(.plain)
            }
        }.padding(.horizontal) }
        .navigationDestination(for: CardElement.self) { element in
            ElementRankingView(element: element)
        }
    }
}
