import SwiftUI

/// 国別の図鑑一覧。各国について「持っているカード数/その国に存在しうるカード数」を出す。
struct CountryListView: View {
    @ObservedObject private var database = CardDatabase.shared
    @ObservedObject private var owned = OwnedCollection.shared

    var body: some View {
        ScrollView { LazyVStack(spacing: 9) {
            CollectionScopeNoticeView()
            ForEach(database.countries) { country in
                NavigationLink(value: country.iso3) {
                    HStack {
                        AsyncImage(url: country.flagImageURL(width: 80)) { phase in
                            if case .success(let image) = phase {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.gray.opacity(0.2)
                            }
                        }
                        .frame(width: 40, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        Text(country.nameJa).lineLimit(1).minimumScaleFactor(0.75)
                        Spacer()
                        let cards = database.cards(forCountry: country.iso3)
                        let ownedCount = cards.filter(owned.owns).count
                        VStack(alignment: .trailing, spacing: 2) { Text(ownedCount == cards.count ? "COMPLETE" : "\(String(ownedCount))/\(String(cards.count))枚").fontWeight(ownedCount == cards.count ? .black : .regular); ProgressView(value: Double(ownedCount), total: Double(max(cards.count, 1))).frame(width: 70).tint(ownedCount == cards.count ? EarthColors.gold : EarthColors.cyan) }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12).frame(minHeight: 58)
                    .background(EarthColors.panel, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(EarthColors.line))
                }
                .buttonStyle(.plain)
            }
        }.frame(maxWidth: .infinity).padding(.horizontal) }
        .navigationDestination(for: String.self) { iso3 in
            CountryDetailView(iso3: iso3)
        }
    }
}
