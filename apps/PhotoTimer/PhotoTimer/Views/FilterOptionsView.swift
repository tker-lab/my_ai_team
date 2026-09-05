import SwiftUI

/// 絞り込み条件の設定画面。MVP確定の7項目すべてをここに置く。
/// どの項目も選択肢は固定リスト or 自動生成されたものだけ(フリー入力の検索欄は作らない。原則1)。
struct FilterOptionsView: View {
    @Binding var settings: FilterSettings
    @ObservedObject private var libraryIndex = LibraryIndex.shared
    @Environment(\.dismiss) private var dismiss

    @State private var customFrom: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customTo: Date = Date()
    /// 【8-7対応】以前は雰囲気・カテゴリを両方選べたが、単一選択への移行でカテゴリが優先され、
    /// 雰囲気の選択が黙って外れていた場合にtrue。この画面を開いた時点の値を保持し、
    /// 「分かりました」を押した時だけfalseに戻す(=毎回出さない)。
    @State private var moodMigrationNoticeVisible = FilterSettingsStore.moodsDroppedByMigrationNoticePending

    var body: some View {
        NavigationStack {
            Form {
                dateSection
                mediaTypeSection
                screenshotSection
                aestheticsSection
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

    // MARK: - よく撮れてる度(2026-09-05追加。iOS 18以降のみ)
    //
    // 【なぜ #available で丸ごと分岐しているか】判定に使うVisionのAPI(CalculateImageAestheticsScoresRequest)
    // 自体がiOS 18以降にしか存在しないため、iOS 17以下の端末ではこの機能そのものが使えない。
    // 設計書の指示どおり「iOS18未満では選択肢を出さない」(中途半端にグレーアウト表示するのではなく、
    // 使えない端末には項目自体を見せない)。

    @ViewBuilder
    private var aestheticsSection: some View {
        if #available(iOS 18.0, *) {
            Section {
                Toggle("よく撮れてる写真を優先する", isOn: $settings.preferHighAesthetics)
                if settings.excludeScreenshots {
                    Toggle("AIで書類・レシートらしい写真も除く", isOn: $settings.strictScreenshotDetection)
                }
            } header: {
                Text("よく撮れてる度")
            } footer: {
                Text("構図・色・ブレ・露出などからAIが「よく撮れているか」を判定します。優先しても除外はされないため、他に該当する写真が無い時は撮れの良し悪しに関わらず表示されます。「書類・レシートらしい写真も除く」は、スクリーンショットではないけれど書類やレシートを撮っただけの写真を追加で見分けます(「スクリーンショットを除く」がオンの時のみ表示)。")
            }
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
                selectMood(tag)
            }
            if moodMigrationNoticeVisible {
                Button {
                    moodMigrationNoticeVisible = false
                    FilterSettingsStore.moodsDroppedByMigrationNoticePending = false
                } label: {
                    Text("分かりました")
                }
            }
        } header: {
            Text("雰囲気・色")
        } footer: {
            if moodMigrationNoticeVisible {
                Text("以前は雰囲気とカテゴリを両方選べましたが、今はどちらか1つだけになりました。カテゴリの選択を優先したため、以前選んでいた雰囲気の指定は解除されています。")
            } else {
                Text("雰囲気・色・カテゴリを通して主題は1つだけ選べます。写真全体の色味からおおまかに分類します。表示時間を長くすると、その間に次の候補を探せるため切り替わりが滑らかになりやすくなります。")
            }
        }
    }

    // MARK: - 場所

    /// 選択済みだが、もう「場所」の選択肢一覧に存在しないID。
    /// 【指摘B対応】以前は場所のID(PlaceCluster.id)の作り方を「クラスタ中心の平均座標」から
    /// 「マス目番号(bucketKey)」に変更したため、その変更より前に選んでいたIDは新しい一覧の
    /// どのIDとも一致しなくなり、絞り込み結果が黙って0件になるのに解除する手段が無かった。
    /// アルバム側(missingSelectedAlbumIDs)と全く同じ考え方で、一覧に存在しないIDを検出して
    /// 解除ボタンを出す。これにより、ID方式の変更前に選んでいた古い設定が残っている場合でも、
    /// このボタン1つで復帰できる(=当時の設定を保存していたUserDefaultsのキー自体を
    /// 新バージョンに切り替える、という大掛かりな移行処理をしなくても済む)。
    private var missingSelectedPlaceIDs: Set<String> {
        settings.selectedPlaceIDs.subtracting(libraryIndex.placeClusters.map(\.id))
    }

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
            if !missingSelectedPlaceIDs.isEmpty {
                Button(role: .destructive) {
                    settings.selectedPlaceIDs.subtract(missingSelectedPlaceIDs)
                } label: {
                    Text("見つからない場所の選択を解除(\(missingSelectedPlaceIDs.count)件)")
                }
            }
        } header: {
            Text("場所")
        } footer: {
            if missingSelectedPlaceIDs.isEmpty {
                Text("あなたが実際に撮影した場所から自動でリストを作成します(位置情報は端末内だけで処理し、地名の変換にのみOS標準の仕組みを使います)。")
            } else {
                Text("以前選んでいた場所が今の一覧に見つかりません。上のボタンで選択を解除できます。")
            }
        }
    }

    // MARK: - カテゴリ

    private var categorySection: some View {
        Section {
            chipGrid(items: libraryIndex.orderedCategories, isSelected: { settings.selectedCategories.contains($0) }, title: { $0.rawValue }) { tag in
                selectCategory(tag)
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
            Text("雰囲気・色・カテゴリを通して主題は1つだけ選べます。解析済みの候補を先に使い、まだ判定していない写真は表示中に探します。多少の誤検出があります。")
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


    private func selectMood(_ value: MoodTag) {
        if settings.selectedMoods.contains(value) {
            settings.selectedMoods.removeAll()
        } else {
            settings.selectedMoods = [value]
            settings.selectedCategories.removeAll()
        }
    }

    private func selectCategory(_ value: CategoryTag) {
        if settings.selectedCategories.contains(value) {
            settings.selectedCategories.removeAll()
        } else {
            settings.selectedCategories = [value]
            settings.selectedMoods.removeAll()
        }
    }
}
