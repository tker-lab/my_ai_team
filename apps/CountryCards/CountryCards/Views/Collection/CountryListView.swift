import SwiftUI

/// 国別の図鑑一覧。各国について「持っているカード数/その国に存在しうるカード数」を出す。
struct CountryListView: View {
    @ObservedObject private var database = CardDatabase.shared
    @ObservedObject private var owned = OwnedCollection.shared

    var body: some View {
        List {
            Section {
                CollectionScopeNoticeView()
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
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

                        Text(country.nameJa)
                        Spacer()
                        let cards = database.cards(forCountry: country.iso3)
                        let ownedCount = cards.filter(owned.owns).count
                        Text("\(ownedCount)/\(cards.count)枚")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationDestination(for: String.self) { iso3 in
            CountryDetailView(iso3: iso3)
        }
    }
}
