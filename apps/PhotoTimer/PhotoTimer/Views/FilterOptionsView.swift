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
                // 「すべて解除」は以前、画面左上の「キャンセル」の定位置(cancellationAction)に
                // 置いていたため誤タップしやすかった(タップすると条件が全部消えてしまう)。
                // 破壊的な操作なので、押しやすいが押し間違えにくい位置(下部ツールバー)に移した。
                ToolbarItem(placement: .bottomBar) {
                    Button("すべて解除", role: .destructive) { settings = .default }
                }
            }
        }
    }

    // MARK: - 日時

    private var dateSection: some View {
        Section {
            Picker("期間", selection: dateRangeBinding) {
                Text("すべて").tag(0)
                Text("今年").tag(1)
                Text("今月").tag(2)
                Text("期間を指定").tag(3)
            }
            if case .custom = settings.dateRange {
                DatePicker("開始", selection: $customFrom, displayedComponents: .date)
                DatePicker("終了", selection: $customTo, displayedComponents: .date)
                    .onChange(of: customFrom) { _, newValue in applyCustomDateRange(from: newValue, to: customTo) }
                    .onChange(of: customTo) { _, newValue in applyCustomDateRange(from: customFrom, to: newValue) }
            }
        } header: {
            Text("日時")
        } footer: {
            if case .custom = settings.dateRange {
                Text("開始日の0時から終了日の24時までが対象になります。")
            }
        }
    }

    /// カスタム期間(開始・終了)を確定させる。以下の2点を自動で補正する(不具合修正):
    ///  1. 開始が終了より後になっていたら、終了を開始に合わせる(範囲が逆転しないようにする)。
    ///  2. 開始日は0時、終了日は23:59:59として扱う。DatePickerで選ぶのは「日付」だけだが、
    ///     内部的にはDateなので時刻の情報も持っている。何もしないと、この画面を開いた瞬間の
    ///     現在時刻がそのまま終了日の時刻として使われてしまい、「終了日当日の夕方以降に撮った
    ///     写真だけ対象から漏れる」という分かりにくい不具合が起きていた。
    private func applyCustomDateRange(from: Date, to: Date) {
        let calendar = Calendar.current
        var to = to
        if from > to {
            to = from
        }
        customFrom = from
        customTo = to

        let startOfDay = calendar.startOfDay(for: from)
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: to) ?? to
        settings.dateRange = .custom(from: startOfDay, to: endOfDay)
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
                default: applyCustomDateRange(from: customFrom, to: customTo)
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

    /// 選択済みだが、もう写真アプリ側のアルバム一覧に存在しないID(=削除された等)。
    /// 【指摘F対応】以前はこの状態になると、一覧に行が出ないため選択を解除する手段が無かった
    /// (絞り込み条件は「アルバムN件」の表示のまま無効になり続けていた)。
    private var missingSelectedAlbumIDs: Set<String> {
        settings.selectedAlbumIDs.subtracting(libraryIndex.albums.map(\.id))
    }

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
            if !missingSelectedAlbumIDs.isEmpty {
                Button(role: .destructive) {
                    settings.selectedAlbumIDs.subtract(missingSelectedAlbumIDs)
                } label: {
                    Text("見つからないアルバムの選択を解除(\(missingSelectedAlbumIDs.count)件)")
                }
            }
        } header: {
            Text("アルバム")
        } footer: {
            if missingSelectedAlbumIDs.isEmpty {
                Text("何も選ばない場合はすべてのアルバムが対象になります。")
            } else {
                Text("選択していたアルバムが写真アプリ側で削除されたため見つかりません。上のボタンで選択を解除できます。")
            }
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
