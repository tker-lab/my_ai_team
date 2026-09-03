import SwiftUI

/// 絞り込み条件の設定画面。MVP確定の7項目すべてをここに置く。
/// どの項目も選択肢は固定リスト or 自動生成されたものだけ(フリー入力の検索欄は作らない。原則1)。
struct FilterOptionsView: View {
    @Binding var settings: FilterSettings
    @ObservedObject private var libraryIndex = LibraryIndex.shared
    @Environment(\.dismiss) private var dismiss

    @State private var customFrom: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customTo: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                dateSection
                mediaTypeSection
                screenshotSection
                albumSection
                moodSection
                placeSection
                categorySection
            }
            .navigationTitle("絞り込み条件")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("すべて解除") { settings = .default }
                }
            }
        }
    }

    // MARK: - 日時

    private var dateSection: some View {
        Section("日時") {
            Picker("期間", selection: dateRangeBinding) {
                Text("すべて").tag(0)
                Text("今年").tag(1)
                Text("今月").tag(2)
                Text("期間を指定").tag(3)
            }
            if case .custom = settings.dateRange {
                DatePicker("開始", selection: $customFrom, displayedComponents: .date)
                DatePicker("終了", selection: $customTo, displayedComponents: .date)
                    .onChange(of: customFrom) { _, _ in settings.dateRange = .custom(from: customFrom, to: customTo) }
                    .onChange(of: customTo) { _, _ in settings.dateRange = .custom(from: customFrom, to: customTo) }
            }
        }
    }

    private var dateRangeBinding: Binding<Int> {
        Binding(
            get: {
                switch settings.dateRange {
                case .all: return 0
                case .thisYear: return 1
                case .thisMonth: return 2
                case .custom: return 3
                }
            },
            set: { newValue in
                switch newValue {
                case 0: settings.dateRange = .all
                case 1: settings.dateRange = .thisYear
                case 2: settings.dateRange = .thisMonth
                default: settings.dateRange = .custom(from: customFrom, to: customTo)
                }
            }
        )
    }

    // MARK: - メディアの種類

    private var mediaTypeSection: some View {
        Section("メディアの種類") {
            Picker("種類", selection: $settings.mediaType) {
                ForEach(MediaTypeFilter.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - スクショ除く

    private var screenshotSection: some View {
        Section {
            Toggle("スクリーンショットを除く", isOn: $settings.excludeScreenshots)
        } footer: {
            Text("メモ代わりに撮ったスクリーンショットなどをスライドショーから外します。")
        }
    }

    // MARK: - アルバム

    private var albumSection: some View {
        Section {
            if libraryIndex.albums.isEmpty {
                Text("アルバムが見つかりませんでした").foregroundStyle(.secondary)
            } else {
                ForEach(libraryIndex.albums) { album in
                    multiSelectRow(
                        title: "\(album.title)(\(album.assetCount)枚)",
                        isSelected: settings.selectedAlbumIDs.contains(album.id)
                    ) {
                        toggle(album.id, in: &settings.selectedAlbumIDs)
                    }
                }
            }
        } header: {
            Text("アルバム")
        } footer: {
            Text("何も選ばない場合はすべてのアルバムが対象になります。")
        }
    }

    // MARK: - 雰囲気(色)

    private var moodSection: some View {
        Section {
            chipGrid(items: MoodTag.allCases, isSelected: { settings.selectedMoods.contains($0) }, title: { $0.rawValue }) { tag in
                toggle(tag, in: &settings.selectedMoods)
            }
        } header: {
            Text("雰囲気・色")
        } footer: {
            Text("写真全体の色味からおおまかに分類します(初めて選ぶ写真は判定に少し時間がかかることがあります)。")
        }
    }

    // MARK: - 場所

    private var placeSection: some View {
        Section {
            if libraryIndex.isBuildingPlaces && libraryIndex.placeClusters.isEmpty {
                HStack {
                    ProgressView()
                    Text("撮影地を集計しています…")
                        .foregroundStyle(.secondary)
                }
            } else if libraryIndex.placeClusters.isEmpty {
                Text("位置情報付きの写真が見つかりませんでした").foregroundStyle(.secondary)
            } else {
                ForEach(libraryIndex.placeClusters) { place in
                    multiSelectRow(
                        title: "\(place.displayName)(\(place.assetCount)枚)",
                        isSelected: settings.selectedPlaceIDs.contains(place.id)
                    ) {
                        toggle(place.id, in: &settings.selectedPlaceIDs)
                    }
                }
            }
        } header: {
            Text("場所")
        } footer: {
            Text("あなたが実際に撮影した場所から自動でリストを作成します(位置情報は端末内だけで処理し、地名の変換にのみOS標準の仕組みを使います)。")
        }
    }

    // MARK: - カテゴリ

    private var categorySection: some View {
        Section {
            chipGrid(items: libraryIndex.orderedCategories, isSelected: { settings.selectedCategories.contains($0) }, title: { $0.rawValue }) { tag in
                toggle(tag, in: &settings.selectedCategories)
            }
            if libraryIndex.isSamplingCategories {
                HStack {
                    ProgressView()
                    Text("よく撮っているカテゴリを集計中(並び順のみ更新されます)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("カテゴリ")
        } footer: {
            Text("犬・猫・人は専用の検出、それ以外は一般的な分類を使うため多少の誤検出があります(見つからないより誤って多く出す方を優先)。")
        }
    }

    // MARK: - 共通パーツ

    private func multiSelectRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
    }

    private func chipGrid<Item: Hashable>(items: [Item], isSelected: @escaping (Item) -> Bool, title: @escaping (Item) -> String, onTap: @escaping (Item) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    onTap(item)
                } label: {
                    Text(title(item))
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isSelected(item) ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundStyle(isSelected(item) ? Color.white : Color.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }
}
