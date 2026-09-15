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
            ZStack {
                EarthBackdrop(variant: .archive)
                VStack(spacing: 0) {
                EarthTopBar(title: "EARTH ARCHIVE") { EmptyView() }
                ArchiveSegmentSwitch(items: ViewMode.allCases.map { ($0, $0.rawValue) }, selection: $mode).padding()

                switch mode {
                case .byCountry:
                    CountryListView()
                case .byElement:
                    ElementListView()
                }
            }
            }.toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// 「国連加盟193カ国のみが対象」「データが無い国のカードは存在しない」という
/// 注意書き(決定事項:バチカン・台湾等への説明を先回りしておく)。
/// 図鑑のどちらの見方からも参照できるよう、共通コンポーネントにしてある。
struct CollectionScopeNoticeView: View {
    @State private var showsDetail = false
    var body: some View {
        Button { showsDetail = true } label: {
            HStack { Text("国連加盟193カ国を収録").font(.caption); Spacer(); Text("詳細").font(.caption.bold()).foregroundStyle(EarthColors.cyan); Image(systemName: "chevron.right") }
                .foregroundStyle(EarthColors.secondary).padding(12).background(EarthColors.panel, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(EarthColors.line))
        }.buttonStyle(.plain)
        .sheet(isPresented: $showsDetail) { SheetWithAdDock { ZStack { EarthBackdrop(variant: .archive); GameModalShell("収録地域について") { Text("データが存在しない国・要素の組み合わせにはカードがありません。バチカン・台湾など国連非加盟地域は対象外です。").foregroundStyle(EarthColors.secondary); Button("閉じる") { showsDetail = false }.buttonStyle(EarthActionButtonStyle()) }.padding(24) } } }
    }
}
