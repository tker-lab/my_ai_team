import SwiftUI

/// 図鑑(コレクション)画面のトップ。「国別に見る」「要素別ランキングで見る」の
/// 2つの見方を切り替えられるようにする(決定事項どおり)。
struct CollectionHomeView: View {
    private enum ViewMode: String, CaseIterable, Identifiable {
        case byCountry = "国別"
        case byElement = "要素別"
        var id: String { rawValue }
    }

    @State private var mode: ViewMode = .byCountry

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("見方", selection: $mode) {
                    ForEach(ViewMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch mode {
                case .byCountry:
                    CountryListView()
                case .byElement:
                    ElementListView()
                }
            }
            .navigationTitle("図鑑")
        }
    }
}

/// 「国連加盟193カ国のみが対象」「データが無い国のカードは存在しない」という
/// 注意書き(決定事項:バチカン・台湾等への説明を先回りしておく)。
/// 図鑑のどちらの見方からも参照できるよう、共通コンポーネントにしてある。
struct CollectionScopeNoticeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("このアプリのカードは国連加盟193カ国が対象です。")
            Text("データが存在しない国・要素の組み合わせにはカードがありません。")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
