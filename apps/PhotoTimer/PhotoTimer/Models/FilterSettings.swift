import Foundation

/// スライドショーの絞り込み条件。MVP確定範囲(2026-09-04)の7項目すべてを持つ。
/// UserDefaults に JSON で保存し、次回起動時も同じ条件を復元する。
struct FilterSettings: Codable, Equatable {
    var dateRange: DateRangeFilter = .all
    var mediaType: MediaTypeFilter = .all
    var excludeScreenshots: Bool = true
    /// 選んだアルバムの localIdentifier の集合。空 = 全アルバム(絞り込みなし)。
    var selectedAlbumIDs: Set<String> = []
    /// 空 = 絞り込みなし(すべての雰囲気を許可)。
    var selectedMoods: Set<MoodTag> = []
    /// 空 = 絞り込みなし。PlaceCluster.id を指す。
    var selectedPlaceIDs: Set<String> = []
    /// 空 = 絞り込みなし。
    var selectedCategories: Set<CategoryTag> = []
    /// 「よく撮れてる度」が高い写真を優先して流すか(2026-09-05追加。iOS 18以降でのみ有効)。
    /// 「近い順に流す」設計(CandidateEngine.score参照)の1軸として、他の条件と同様に
    /// スコアへ加算する形にしている(足切りはしない。低いスコアの写真も、他に条件が無ければ流れる)。
    var preferHighAesthetics: Bool = false
    /// AI(よく撮れてる度のisUtilityフラグ)も使って、書類・レシート・メモ写真などの
    /// 「実用目的の画像」をスクリーンショットと同様に除外するか(2026-09-05追加。iOS 18以降のみ)。
    /// `excludeScreenshots` がメタ情報(mediaSubtypes)だけを見るのに対し、こちらは画像の中身を見て
    /// 判定する分だけ精度が高いが、判定に画像解析(Vision)が必要になる。
    /// `excludeScreenshots` がオフの時にこれだけオンにしても意味が無いため、UI側(FilterOptionsView)は
    /// `excludeScreenshots` がオンの時だけこの項目を出す。
    var strictScreenshotDetection: Bool = false

    /// 選んだ「保存したリスト」(CustomPhotoList.id)。保存形式の互換性のためSetのまま持つが、
    /// 常に高々1件へ正規化する。リスト選択中は他の絞り込みを一切使わない最優先条件。
    var selectedCustomListIDs: Set<String> = []

    /// 現在選んでいるリスト。旧版で複数選択されたデータが残っていても、決定的な1件だけを使う。
    var selectedCustomListID: String? {
        selectedCustomListIDs.sorted().first
    }

    var isCustomListSelected: Bool { selectedCustomListID != nil }

    /// 画像解析(雰囲気・カテゴリ・よく撮れてる度優先・AIでのスクショ除外強化)が必要かどうか。
    /// 原則2の「遅延評価」に載せるべき条件がひとつでもあるかの判定に使う。
    var needsImageAnalysis: Bool {
        if isCustomListSelected { return false }
        return !selectedMoods.isEmpty || !selectedCategories.isEmpty || preferHighAesthetics || strictScreenshotDetection
    }

    static let `default` = FilterSettings()

    init() {}

    /// 【2026-09-05追加:項目を増やしても既存の保存データを壊さないためのカスタムデコード】
    /// PlaybackSettingsで発覚したのと同じ罠(Swiftの自動生成Decodableは、構造体にあるプロパティの
    /// キーがJSON側に無い場合、デフォルト値を無視してデコード全体を失敗させる)がこの構造体にも
    /// 当てはまる。`selectedCustomListIDs` を追加する今回、これより前に保存されていた設定ファイルは
    /// このキー自体を持たないため、自動生成のデコードのままでは読み込み全体が失敗し、CEOが選んでいた
    /// 日時・アルバム・雰囲気などの設定がまとめて既定値に巻き戻ってしまう
    /// (詳細はPlaybackSettings.swiftの同種のコメント、および app-team部署メモリ参照)。
    /// `decodeIfPresent` を使い、無ければデフォルト値を使う自前の初期化にすることで回避する。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dateRange = try container.decodeIfPresent(DateRangeFilter.self, forKey: .dateRange) ?? .all
        mediaType = try container.decodeIfPresent(MediaTypeFilter.self, forKey: .mediaType) ?? .all
        excludeScreenshots = try container.decodeIfPresent(Bool.self, forKey: .excludeScreenshots) ?? true
        selectedAlbumIDs = try container.decodeIfPresent(Set<String>.self, forKey: .selectedAlbumIDs) ?? []
        selectedMoods = try container.decodeIfPresent(Set<MoodTag>.self, forKey: .selectedMoods) ?? []
        selectedPlaceIDs = try container.decodeIfPresent(Set<String>.self, forKey: .selectedPlaceIDs) ?? []
        selectedCategories = try container.decodeIfPresent(Set<CategoryTag>.self, forKey: .selectedCategories) ?? []
        preferHighAesthetics = try container.decodeIfPresent(Bool.self, forKey: .preferHighAesthetics) ?? false
        strictScreenshotDetection = try container.decodeIfPresent(Bool.self, forKey: .strictScreenshotDetection) ?? false
        selectedCustomListIDs = try container.decodeIfPresent(Set<String>.self, forKey: .selectedCustomListIDs) ?? []
    }

    /// 雰囲気・色・カテゴリは全体で1つだけ選べる「主題」。旧版の複数選択設定も壊さず、
    /// 決定的に1件へ縮める。日時・場所などの整理条件には触れない。
    mutating func normalizeSingleSubject() {
        if let category = selectedCategories.sorted(by: { $0.rawValue < $1.rawValue }).first {
            selectedCategories = [category]
            selectedMoods.removeAll()
        } else if let mood = selectedMoods.sorted(by: { $0.rawValue < $1.rawValue }).first {
            selectedMoods = [mood]
            selectedCategories.removeAll()
        }
    }

    /// v10: 自作リストは複数の条件を掛け合わせる入口ではなく、表示内容を丸ごと決める
    /// 「保存済みの選抜」として扱う。旧版の複数選択値は文字列順の先頭へ安全に縮める。
    mutating func normalizeSingleCustomList() {
        if let selectedCustomListID {
            selectedCustomListIDs = [selectedCustomListID]
        }
    }
}

// MARK: - 永続化
///
/// 【2026-09-04変更(指摘G対応)】
/// 以前は UserDefaults に保存していたが、UserDefaults(標準の保存領域)の中身は既定で
/// iCloudバックアップ・iTunes/Finderバックアップの対象に含まれる。選んだ「場所」
/// (selectedPlaceIDs)はマス目番号(例 "715.0_2795.0")で、割り算を戻すだけで
/// 自宅周辺などの座標が復元できてしまうため、**CEOが「バックアップ対象外にする」と
/// 決定した事項**に反していた(場所データ本体〔PlaceCluster〕は既に対応済みだったが、
/// 「どの場所を選んだか」という設定はここが漏れていた)。
/// 解析結果(AssetAnalysis)・場所データ(PlaceCluster)と同じ「端末内ファイル+
/// isExcludedFromBackup」の方式に統一する。
enum FilterSettingsStore {
    /// 移行元(旧保存先)。読み込み専用として残す。移行が済んだらこのキーは削除する。
    private static let legacyDefaultsKey = "PhotoTimer.FilterSettings.v1"

    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("filter_settings.json")
    }()

    static func load() -> FilterSettings {
        #if DEBUG
        // 回帰テスト専用。保存済み設定に左右されず、画像解析が必要な厳しい条件で探索中断を試す。
        if ProcessInfo.processInfo.environment["PHOTOTIMER_UI_TEST_SEARCH_BUDGET"] == "1" {
            var testSettings = FilterSettings.default
            testSettings.selectedMoods = [.dark]
            testSettings.selectedCategories = [.fireworks]
            return testSettings
        }
        #endif
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(FilterSettings.self, from: data) {
            let migrated = migrate(decoded)
            // 【8-7対応・2026-09-05】以前は移行後の値をメモリ上で返すだけで、ディスク(filter_settings.json)
            // 自体は移行前のまま書き換えていなかった。実害は無い(次回起動時も同じ移行を毎回やり直すだけ)が、
            // 「移行済みの値を正」として扱うなら、その場でディスクへ書き戻しておくのが素直な形なので揃える。
            if migrated != decoded {
                save(migrated)
            }
            return migrated
        }
        // 新しい保存先にまだ何も無い場合、旧保存先(UserDefaults)に残っている可能性がある
        // (アップデート前から使っていた場合)。あれば1回だけ読み込み、新しい保存先に書き直した上で
        // 旧データは削除する(そのままだとバックアップに残り続けてしまうため)。
        if let legacyData = UserDefaults.standard.data(forKey: legacyDefaultsKey),
           let legacyDecoded = try? JSONDecoder().decode(FilterSettings.self, from: legacyData) {
            let migrated = migrate(legacyDecoded)
            save(migrated)
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            // 通常、UserDefaultsへの変更はOS側が適切なタイミングで自動的にディスクへ反映するため
            // synchronize() の明示呼び出しは非推奨・基本的に不要とされている。ただしこの移行処理は
            // 「アプリの生涯で最大1回だけ」しか通らない特別な経路であり、かつ削除したはずのキーが
            // バックアップに残ってしまうことを確実に防ぎたい(CEO決定事項)ため、念のためここだけ
            // 明示的に同期させ、削除がすぐ確実にディスクへ反映されるようにしている。
            UserDefaults.standard.synchronize()
            return migrated
        }
        return .default
    }

    /// 【2026-09-05追加】「緑」を選択肢から削除した(FixedChoices.swift参照)ことに伴う移行処理。
    /// 過去に「緑」を選んでいた場合、その選択だけを静かに外す(他の選択〔アルバム・雰囲気の他の項目・
    /// カテゴリ等〕はそのまま維持する)。enumのケース自体は残しているのでデコード自体は失敗しないが、
    /// 外さないままだと「UIには出ない・解除もできない・でも一致する写真は二度と現れない」という
    /// 気づけない絞り込み条件が残り続けてしまうため、読み込み時に必ず取り除く。
    private static func migrateAwayFromGreen(_ settings: FilterSettings) -> FilterSettings {
        guard settings.selectedMoods.contains(.green) else { return settings }
        var migrated = settings
        migrated.selectedMoods.remove(.green)
        return migrated
    }

    /// 【2026-09-05追加】「飲み物」を選択肢から削除した(FixedChoices.swift参照)ことに伴う移行処理。
    /// 考え方は migrateAwayFromGreen と同じ: 過去に「飲み物」を選んでいた場合、その選択だけを
    /// 静かに外す(他の選択はそのまま維持する)。
    private static func migrateAwayFromDrink(_ settings: FilterSettings) -> FilterSettings {
        guard settings.selectedCategories.contains(.drink) else { return settings }
        var migrated = settings
        migrated.selectedCategories.remove(.drink)
        return migrated
    }

    private static func migrate(_ settings: FilterSettings) -> FilterSettings {
        var migrated = migrateAwayFromGreen(settings)
        migrated = migrateAwayFromDrink(migrated)
        // 【8-7対応・2026-09-05】雰囲気・カテゴリを両方選んでいた旧設定は、単一選択への移行で
        // カテゴリが優先され、雰囲気の選択が黙って外れる。アルバム・場所には「見つからない選択を
        // 解除」という気づける導線があるのに、ここだけ無言だったという指摘への対応として、
        // 実際に雰囲気が外れる時だけ「お知らせ待ち」を立てておく。FilterOptionsView側が
        // これを見て、雰囲気のセクションに一度だけ説明を出す(見た後は自分でfalseに戻す)。
        if !migrated.selectedMoods.isEmpty, !migrated.selectedCategories.isEmpty {
            moodsDroppedByMigrationNoticePending = true
        }
        migrated.normalizeSingleSubject()
        migrated.normalizeSingleCustomList()
        return migrated
    }

    /// 【8-7対応】UserDefaultsに持たせる、表示専用の一時的な「お知らせ待ち」フラグ。
    /// 場所・アルバムの選択(座標・個人の写真の内訳が推測できる情報)とは違い、
    /// 「移行の説明をまだ見せていない」というだけの情報でしかないため、
    /// filter_settings.json(バックアップ対象外にしている本体)とは分けてUserDefaultsに置く。
    private static let moodsDroppedByMigrationNoticeKey = "PhotoTimer.FilterSettings.moodsDroppedByMigrationNoticePending"

    static var moodsDroppedByMigrationNoticePending: Bool {
        get { UserDefaults.standard.bool(forKey: moodsDroppedByMigrationNoticeKey) }
        set { UserDefaults.standard.set(newValue, forKey: moodsDroppedByMigrationNoticeKey) }
    }

    static func save(_ settings: FilterSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
        BackupExclusion.exclude(fileURL)
    }
}
